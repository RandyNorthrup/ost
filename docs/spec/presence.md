# Publishing your own presence — Teams desktop behaviour (spec)

Source: the Teams client itself. Its data-layer web worker
(`teamsjs2/worker/*.worker.js`) and UI bundles (`teamsjs2/all/*.js`) were
read module by module. Feature-flag values were read from the running
Windows app on winpc (signed in as ost-test1, web build string
`26101515220`) through the WebView2 debugger, read-only. Module ids, and
byte offsets for the very large modules, are given so this can be
re-checked against later builds.

Worker files are named here by their suffix: `services_i`
(`precompiled-web-worker-inner_services_i-*`), `b`, `c`, `d`, `i`.

## Flags that decide the behaviour
Defaults come from `config-prod-*.js` (presence block at offset 900818).
"Live" is what winpc reports. Platform ids (module 23950 `PU`): Web = 1415,
Maglev = 48, MaglevT21 = 49 (Windows desktop), MaglevMacT21 = 50,
MaglevRoomsT21 = 51.

| flag | value on desktop | effect |
|---|---|---|
| `enablePresenceInWorker` | true | presence runs in the worker at all |
| `enableReportingUserActivityThroughTrouterByPresence` | true (live) | active/inactive goes over Trouter `user.activity`, not `reportmyactivity`; `activityReporting: "Transport"`; heartbeat every hour |
| `enableRetrievingEndpointIdOnlyFromPresenceManager` | true (live) | the presence endpoint id **is** the Trouter endpoint id (epid) |
| `shouldCheckMachineState` | true on 48–51 only | desktop: "active" means the machine is unlocked |
| `enableWebMachineIdle` (core) | true on 1415/1454 only | web uses its own machine tracker |
| `enableCallingClientState` | true (live) | calls publish Busy/Presenting; client-state changes don't publish on desktop |
| `enableStatesAggregationForUserActivity` | false | — |
| `shouldCheckMachineIdleState` | only `buildType: local` | system idle does not drive `user.activity` in shipped builds |
| `shouldDebouncePublishPresenceWhenStateChange`, `debouncePublishPresenceTimeInMs` | true, 1000 | state-change publishes are debounced 1 s |
| `enablePresenceSetActivityDebounce`, `presenceSetActivityDebounceIntervalInMs` | true, 1000 | `user.activity` changes debounced 1 s (not for Locked) |
| `presencePostHeartbeatTrouterIntervalInMs` | 3 600 000 | heartbeat interval with Trouter reporting |
| `presencePostHeartbeatIntervalInMs` | 120 000 | heartbeat interval without it |
| `presenceStrategyPollingIntervalInMs` | 60 000 | the interval tick that counts toward the heartbeat |
| `enableCreateEndpointAfterTrouterConnects`, `createEndpointAfterTrouterConnectsDelayInMs` | true, 240 000 | endpoint re-PUT on Trouter reconnect throttle |
| `enableRecreateEndpointThrottle`, `endpointResponseLatencyInMs` | true, 10 000 | see "Startup" |
| `enableSkipInvalidEndpointCreation` | true | no endpoint PUT while the computed state is BeRightBack |
| `enableSerializingPublishPresence` | true | one publish in flight; the newest pending one runs after it |
| `enableAfdPresenceEndpoint` | true (live) | base URL is the AFD `presenceUPS` one |
| `enablePresenceServiceRetries`, `presenceServiceMaxRetries` | true, 3 (live; code default 10) | retries |
| `enableSetPresenceConcurrencyControl`, `enableSetPresenceThrottleControl`, `preventRedundantSetPresenceExpiryInMs` | true, true, 300 000 | duplicate/too-fast status changes are dropped |
| `appIdleTimeoutInMs`, `appLongIdleTimeoutInMs` (core) | 300 000, 1 200 000 | client Inactive / LongInactive |
| `machineIdlePollingIntervalMs`, `disableSystemIdlePolling` (core) | 20 000, false on 49–51 (true elsewhere) | system idle polling |
| `idleUpdateOnMachineLock` (core) | true on 49–51 | locking the machine makes the client Inactive |
| `onlyPriorityCallsInDnD` (notifications) | true | incoming calls are not exempt from DND by themselves |
| `enablePriorityContactsNotifications` | true on 49–51 | priority-access contacts break through DND |
| `enableUrgentToastsContentFixes` | true | see "Do not disturb" |

## The presence service (`services_i` module 93846, `PresenceService`)
- **Base URL**: `discover.regionGtm("presenceUPS")` when
  `enableAfdPresenceEndpoint` is on, else `regionGtm("unifiedPresence")`.
  Live values: `presenceUPS` = `https://teams.microsoft.com/ups/noam`,
  `unifiedPresence` = `https://presence.teams.microsoft.com`. Paths are
  appended to the base.
- **Auth**: with `enableSendPresenceTokenToUPS` (live true), AFD requests
  use `authenticationService.authorizeRequest(req, H)`. H is a resource
  passed into the factory that wasn't traced. Non-AFD requests use
  `authorizeByUrl`. → TODO: find H's audience. OST's
  `presence.teams.microsoft.com/.default` token works against the non-AFD base.
- **Redirects**: at most 10, each sent with the header
  `BehaviorOverride: redirectAs404`. Under AFD the new base is
  `{origin}{first "/ups…/…/" path segment pair}` of the redirect URL (the
  `/\/ups.*?\/.*?\//` match).
- **Retries**: when `enablePresenceServiceRetries` is on, a request is
  retried on SERVER_TIMEOUT, RejectHttpError, FailedToFetch, TimedOut and
  TransformFailed. The limit is `presenceServiceMaxRetries`. The delay is
  `1000 × 1.5^n` ms.
- **Headers on every request**:
  - `Content-Type: application/json`;
  - `x-ms-client-type`, `x-ms-client-version`, `x-ms-session-id`, and empty
    `x-ms-request-id` and `x-ms-object-id` (module 24139);
  - `x-ms-client-user-agent: Teams-V2-Desktop` (or `Teams-V2-Web` when
    platformId == Web);
  - `x-ms-endpoint-id: <endpoint id>` when known;
  - `x-ms-client-caller: <callerInfo>` when given;
  - `x-ms-correlation-id: <scenario id, or a new uuid v4>`;
  - in the consumer ("life") environment, `x-ms-client-consumer-type: teams4life`.

| model | method + path | body | success |
|---|---|---|---|
| publishEndpointPresence | PUT `v1/me/endpoints/` | the endpoint presence object (below) | 200, 201; response ignored (`enableNoOpResponseTransformForPublishPresence`) |
| deleteEndpoint | DELETE `v1/me/endpoints/{endpointId}` | none | 200 |
| postActiveEndpoint (heartbeat) | POST `v1/me/reportmyactivity/` | `{"endpointId": id, "isActive": bool}` | 200 |
| setMyStatus | PUT `v1/me/forceavailability/` | the status request, or **no body** to reset | 200 |
| setStatusNote | PUT `v1/me/publishnote` | `{"message": …, "expiry": …}` | 200 |
| setWorkLocation | PUT `v1/me/workLocation/` | `{location: 0..3, expirationTime, locationId?, locationIdType?}` | 200 |
| getPresence | POST `v1/presence/getpresence/` | `[{mri, source?, etag?}]` | 200 |
| subscribePresence | POST `v1/pubsub/subscriptions/{endpointId}` | `{trouterUri, shouldPurgePreviousSubscriptions, subscriptionsToAdd:[{mri,source:"ups"}], subscriptionsToRemove}` | 200 |

Work-location enum (module 72648 `zi`): Unknown = 0, Office = 1, Remote = 2,
TimeOff = 3. `locationIdType`: Unspecified = 0, Directory = 1.

## The endpoint presence object
Fields: `id`, `availability`, `activity`, `activityReporting`, `deviceType`.
- `activityReporting` = `"Transport"` when
  `enableReportingUserActivityThroughTrouterByPresence` is on, else
  `"Direct"`. It is set on every create and publish (module 67431 `IF`).
- `deviceType` is filled by the service wrapper when missing: `"Desktop"`,
  or `"Web"` on the web platform. The user-agent header uses the same word.
- **Accepted by the service wrapper** (94897 `v2`): `id` must be non-empty,
  and (availability, activity) must be one of these pairs (no activity is
  allowed only with Available):

  | availability | activity |
  |---|---|
  | Available | Available, or none |
  | Busy | InACall |
  | Busy | InAConferenceCall |
  | DoNotDisturb | Presenting |
  | Away | Away |

- **Accepted by the manager** before a state-change publish or an endpoint
  create (67431 `$V`): Available + (Available|empty), Busy +
  (InACall|InAConferenceCall), DoNotDisturb + Presenting. Anything else,
  including BeRightBack and null, is **not sent**. The manager logs
  "invalid combination" and treats it as success.
- So the client itself only ever publishes these three pairs:
  - Available/Available;
  - Busy/InACall;
  - DoNotDisturb/Presenting.

  It never publishes Away, BeRightBack, InAConferenceCall or InAMeeting.
  Those come from the service: forced status, the calendar, or missing
  activity.
- JSON key order as sent:
  - create: `id, availability, activity, activityReporting, deviceType`;
  - state-change publish: `id, activity, availability, activityReporting, deviceType`;
  - call-state publish: `availability, activity, id, activityReporting, deviceType`.

## What the client computes (worker `b` module 67431)
States (worker `c` module 56805):
- client: Initializing, Unrecoverable, LongInactive, Inactive, Active, VeryActive;
- machine (lock): Initialized, Unknown, Locked, Active;
- machine idle: Unknown, Idle, Active.

- `HQ(isDesktop, webIdle, machine)` = "machine state is meaningful". It is
  true on desktop, and on web with `enableWebMachineIdle` once the machine
  state is past Initialized/Unknown.
- **isAppActive** (`KH`): when the machine state is meaningful, `machine ==
  Active`. Otherwise false for client Inactive, LongInactive or
  Unrecoverable, and true for anything else. So on desktop, **client idle
  never makes you inactive; only locking (or suspending) the machine does.**
- **State → (availability, activity)** (`z6`):
  - When the machine state is meaningful:
    - client VeryActive → (null, null);
    - machine Active → (Available, Available);
    - otherwise → (BeRightBack, BeRightBack).
  - Otherwise:
    - client Active → (Available, Available);
    - client Inactive or LongInactive → (BeRightBack, BeRightBack);
    - anything else → (null, null).
- **With calls** (`rU`, used because `enableCallingClientState` is on):
  - calling state IN_A_CALL → (Busy, InACall);
  - calling state PRESENTING → (DoNotDisturb, Presenting);
  - otherwise the result of `z6`.
- **Call-state publish** (`bR`):
  - IN_A_CALL → (Busy, InACall);
  - PRESENTING → (DoNotDisturb, Presenting);
  - anything else (NOT_IN_A_CALL) → (Available, Available).

## When the client publishes (PresenceManager `io`, worker `b` ≈3 741 000; PresenceSyncStrategy, worker `c` module 64130)

### Startup and Trouter connect
- With Trouter reporting on, `onStartup` creates **no** endpoint.
  (Otherwise it calls `createEndpoint("presence-sync-strategy-on-startup")`.)
- When Trouter reaches Connected, `onTrouterConnected`:
  - stores the Trouter endpoint id;
  - then **creates the endpoint** (PUT `v1/me/endpoints/`, caller
    `presence-sync-strategy:TrouterStateChanged`) if the epid changed, or if
    `shouldRecreateEndpoint()` says so;
  - otherwise does nothing.
- `shouldRecreateEndpoint()`:
  - false if the last successful create or publish ended less than 240 s ago;
  - false if a create or publish started less than 10 s ago and hasn't
    failed;
  - true otherwise.
- **Create-endpoint body** (worker `c` 69271 class `SI`): `{id: epid,
  availability: a ?? "Available", activity: b ?? "Available",
  activityReporting}`, where (a, b) come from `rU` (above).
  - If the computed pair fails `$V` (machine locked → BeRightBack), creation
    is **skipped** (`enableSkipInvalidEndpointCreation`).
  - Client VeryActive gives (null, null), which becomes Available/Available.
  - Job: PresenceCreateEndpointJob (worker `b` 73643), priority HIGH, 300 s
    timeout. It rejects an empty id.
- Right after the first connect, the strategy reports the user's activity
  state over Trouter. See "Activity over Trouter".
- Whenever a publish **or** heartbeat gets **404**, the client re-creates
  the endpoint (`SF.publishPresenceInternal`, `pF.postHeartbeat`, then
  `createEndpoint`).

### Machine lock / unlock (desktop)
- Lock state comes from the host (`osutils.registerForSessionStateChanged`
  Locked/Unlocked/Suspending/Resumed, plus `AppStateSyncMessage
  {isMachineLocked}`). The host-state provider is async-entry module
  16100, class `tG` ≈2 580 498. It reaches the worker as
  `MachineLockState` → `onMachineStateChanged`.
- `processAppStateChange`:
  - computes isAppActive;
  - when in a call or active, schedules a **debounced (1 s) state-change
    publish**;
  - when active, also refreshes presence subscriptions (at most hourly) or
    polls subscribed presences (at most every 120 s).
- The publish then sends `rU`'s pair:
  - unlocked → **Available/Available**;
  - in a call → Busy/InACall or DoNotDisturb/Presenting;
  - locked → BeRightBack, which **is not sent**.
- So locking sends nothing on `v1/me/endpoints`. The service learns about
  it from the Trouter `user.activity: inactive`. See below.

### Client idle (Teams window input)
- The IdleTracker (async-entry module 955598) watches these events on the
  Teams window: scroll, DOMMouseScroll, mousewheel, touchstart, touchmove,
  mousemove, keydown.
  - Input sets the client Active.
  - After `appIdleTimeoutInMs` (300 s) without input it goes Inactive.
  - After `appLongIdleTimeoutInMs` (1200 s) it goes LongInactive.
- It also goes Inactive when the document is hidden (if visibility tracking
  is on).
- Locking makes an Active client Inactive (`idleUpdateOnMachineLock`).
  Unlocking restarts the long-idle timer.
- VeryActive is set while in a call or sharing (see "Calls"). Idle doesn't
  override VeryActive.
- **On desktop, client-state changes don't publish anything**:
  `onClientStateChanged` returns before `processAppStateChange` when
  `enableCallingClientState && isDesktop`. They don't send Trouter activity
  either (the machine state is meaningful, so the client-state branch is
  skipped).
- LongInactive (or locked, or offline) only pauses polling: no sync, no
  heartbeat, no subscribe.

### System idle
- The machine idle tracker (async-entry 16100, class `QV` ≈2 573 301) polls
  the host's `osutils.getSystemIdleTime()` (seconds) every
  `machineIdlePollingIntervalMs` (20 s), but **only while the client is
  Inactive or LongInactive**.
- System idle of 300 s or more (`machineIdleThresholdMs`, default 300 000)
  → Idle. Locked → Idle. Client Active or VeryActive → Active.
- In shipped builds this changes nothing in presence:
  `onMachineIdleStateChanged` acts only with
  `enableStatesAggregationForUserActivity` or `shouldCheckMachineIdleState`,
  and both are off.
- **Verified on winpc (2026-11-06)**: the PC was left with no input and not
  locked for more than 11 minutes (07:00–07:12 UTC). ost-test1 stayed
  **Available** the whole time (read each minute from the client's own
  status). So plain idleness never makes a desktop user Away; only lock,
  sleep or a call changes presence. OST does the same.
- **Calls, verified live (2026-11-06)**: Randy's Teams web called OST (as
  ost-test1). While the call was up, ost-test1's status in the winpc
  client read "In a call"; after the hang-up it read "Available".

### Calls, meetings, presenting
- The calling stack emits `callingClientStateEvent {inCall,
  isScreenSharing, globalInCall, globalIsScreenSharing}`. The emitter is
  module 527114 `emitCallingStateChange`. With
  `enableIsScreenSharingInCallingClientStateEvent` off, isScreenSharing is
  forced false.
- apps-calling module 361789 maps the event:
  - `inCall && isScreenSharing` → mutation `setCallStatePresence("PRESENTING")`;
  - else `inCall` → `"IN_A_CALL"`;
  - else `"NOT_IN_A_CALL"`.
- The same module sends `updateClientStateVeryActive(isVeryActive: inCall ||
  isScreenSharing, source: "Calling")`. The broadcast screen (599954) does
  the same with IN_A_CALL / NOT_IN_A_CALL.
- A meeting is a call here. The client has no separate meeting state.
- Worker resolver `setCallStatePresence` (worker `d` 60233) calls
  `publishPresenceWithCallState`:
  - Skipped if the calling state equals the last one
    (`enableCallingClientState`).
  - Otherwise it publishes **immediately**, with no `$V` filter and no
    debounce:
    - IN_A_CALL → Busy/InACall;
    - PRESENTING → DoNotDisturb/Presenting;
    - NOT_IN_A_CALL → **Available/Available** (even if the machine is locked).
  - On failure or 404 it creates the endpoint.
- While in a call, a state-change publish (lock/unlock) also sends the
  call pair, through `rU`.

### Serialising
- While one publish is in flight, the newest request waits as "pending"
  (older pending ones are replaced). It is sent when the first finishes,
  with caller `<caller>-serialized` (`enableSerializingPublishPresence`).
- On success the endpoint's `lastActiveTimestamp` is updated in the local
  store.

## Activity over Trouter (worker `c` 64130, trouter lib worker `i` module 983)
- State is `active` or `inactive`. On desktop it is **Inactive iff the
  machine is Locked**, else Active (`getUserActivityState`).
- `setUserActivityWithScenario`:
  - debounces 1 s, except when the new machine state is Locked, which is
    reported at once;
  - drops a repeat of the last reported state.
- Wire: a socket.io event `user.activity` with args `{"state": "active" |
  "inactive", "cv": "<correlation vector>"}`. The cv is incremented per send.
- **On (re)connect it is sent twice**: `sendUserActivityStateMultiple(2)`,
  the second copy after `userActivitySecondResendDelayMs` (10 000).
- **On a change it is sent once.**
- The server acks through the emit callback. That raises
  `TrouterUserActivityStateAccepted(cv)`.
- No ack within `userActivityResponseTimeoutMs` (10 000) → the connection
  is treated as broken and reconnects.
- When `updateUserActivityDuringConnectionAttempt` (default true), the
  current state is also put on the connect URL query as
  `userActivity=<urlencoded {"state","cv"} JSON>`.
- Over the xhr-polling transport, a change forces a reconnect instead.
- With the flag off, the Trouter notification provider (worker `c` 3949)
  sends Active on connect/start and Inactive on stop. Desktop doesn't use
  this path.

## Heartbeat (`reportmyactivity`)
- Ticks every `presenceStrategyPollingIntervalInMs` (60 s). It counts up to
  `presencePostHeartbeatTrouterIntervalInMs` (3 600 000 → **hourly**). With
  Trouter reporting off, the target is `presencePostHeartbeatIntervalInMs`
  (120 000).
- The tick is skipped (the counter keeps counting) while the client is
  LongInactive, the machine is Locked, or the app is offline
  (`enableSkipPresenceSyncWhileLongInactive`).
- Body `{"endpointId": epid, "isActive": isAppActive}`. On desktop,
  isActive = machine unlocked. Caller `presence-sync-strategy:onInterval`.
  Priority NORMAL.
- Ignored if the previous heartbeat is still in flight. A 404 → create the
  endpoint.
- With Trouter reporting **off**, every state change also sends a
  heartbeat. With it on (desktop), it doesn't.

## Self-presence watchdog
- If the service pushes your own presence as Away or Offline with no
  `forcedAvailability`, while the client believes you are active, a timer
  starts (`awayPresenceTimerIntervalInMs`, 120 000).
- When it fires:
  - the endpoint is re-created (`enableRecreateEndpointWhenInconsistentPresence`,
    throttled to once per 600 s);
  - your own presence is polled (at most hourly).
- A later non-Away push cancels the timer.

## Forced status (`forceavailability`)
- Request built by worker `d` 49107 `bv`: `{"availability": A}`, plus
  `"activity": "OffWork"` **only** for Offline, plus
  `"desiredExpirationTime": ISO` when the expiry isn't Never.
- Validated by 94897 `hR`:
  - no body is OK;
  - Offline needs activity OffWork;
  - otherwise there must be no activity, and A must be one of Available,
    Busy, DoNotDisturb, BeRightBack, Away.
- **Reset status** → `resetPresence` → PUT with **no body**. Caller
  `<caller>-reset`.
- Dropped (no request):
  - an identical request is still in flight;
  - a request comes within 10 s of the previous one while that one is
    pending;
  - the requested availability and expiry equal the current forced ones.
    This check runs only while a request is pending or within 300 s of the
    last success.
- On success the cached self presence gets `availability = A` and
  `activity = cu(A)` (Offline → OffWork, others the same word), then your
  presence is re-read.

## Expiry values (worker `d` 49107 `Rn`; services_i 15583, 74588)
All are computed from the current local time and sent with `toISOString()`.

| key | expiry |
|---|---|
| HalfHour | now + 30 min |
| OneHour | now + 1 h |
| TwoHours | now + 2 h |
| FourHours | now + 4 h |
| Today | today 23:59:59.999 local |
| ThisWeek | **the Saturday of this week, 00:00:00.000 local** (startOfDay(endOfWeek), weekStartsOn Sunday) |
| Never / Custom / other | the custom date if given, else `new Date(9999, 11, 31)` local |

For a forced status, Never (the 9999 date) means **no**
`desiredExpirationTime`. For a status note the 9999 date **is** sent.

## Profile menu (nova me control, async-entry module 304255)
- **Status list**: built from the GraphQL `availabilityOptions`. Labels:
  - Available (`nova:me_control_presence_availability_available`);
  - Busy;
  - Do not disturb;
  - Be right back;
  - Appear away (`…_appear_away`, availability Away);
  - Appear offline (`…_appear_offline`, Offline);
  - Reset status (`…_reset_status`).
- **Duration** page (`nova:me_control_presence_availability_duration` =
  "Duration"; "Reset status after", main-locale `kd9ux97ma`):
  - choices HalfHour, OneHour, TwoHours, Today, ThisWeek, then Custom with
    "Expiration date" / "Expiration time" pickers;
  - labels "30 minutes", "1 hour", "2 hours", "Today", "This week", "Custom";
  - **default Today**;
  - submit "Done", which sends `setPresenceAvailability({availability,
    expiry: {preDefined, custom}})`;
  - success alert "Status saved" (`kd5724cmd`).
- **Set status message** (`nova:me_control_set_status_message_text`):
  - Header: Back button, "Set status message", and your UPN.
  - Textarea: placeholder "Type your status message here", **max 280
    chars**, counter `{{length}} / {{maxLength}}`. The manager rejects
    anything over 2000.
  - Checkbox **"Show when people message me"** (`k53yqefrm`), with an info
    icon and the tooltip "Your status message will show above the compose
    message box when someone sends you a message or @mentions you."
    (`k5up498kq`). Its initial value is the current note's `pinStatusToChat`.
  - "Clear status message after" (`nova:me_control_set_status_message_clear_after`):
    - choices **Never (default)**, Today, 1 hour, 4 hours, This week,
      Custom (date + time);
    - `data-tid`s `me-control-set-status-message-menu-item-{never|today|one-hour|four-hours|this-week|custom}`.
  - Primary button: "Done", or "Saving..." while in flight. Disabled while
    saving, or while the text is empty and there is no existing note.
  - Link "Schedule out of office".
  - Errors: "Failed to set status note, please try again." and "Failed to
    set status note, try again when you're online.". Success: "Status
    message saved".
- **Sending a status message**:
  - The mutation is `setPresenceStatusNote({message, pinStatusToChat,
    expiry: {preDefined, custom}})`, then the worker resolver
    `setStatusNote({message, expiry, expiryDate})`.
  - The message HTML is normalised when `enableAtMentionInStatusNote` is
    on (60233 `_`):
    - it is wrapped in `<p>`;
    - `<readonly mri>` mentions become `<span itemtype="http://schema.skype.com/Mention" itemscope itemid=N data-itemprops='{"mri","mentionType":"person"}'>`;
    - `<pinnednote>` elements are kept.
  - Then PUT `v1/me/publishnote` with `{"expiry": ISO, "message": html}`.
- **Pinned** ("Show when people message me") is stored in the message
  itself: the text followed by `<pinnednote></pinnednote>`. Readers test
  `message.indexOf("<pinnednote></pinnednote>") > 0` (compose module 382442
  `It`; 304255 `oy` keeps the element after the text). **Confirmed** from a
  real request on winpc (2026-11-06): `PUT https://teams.microsoft.com/ups/noam/v1/me/publishnote`
  `{"expiry":"9999-12-31T08:00:00.000Z","message":"<p>OST test 41 status message</p><pinnednote></pinnednote>"}`
  (Never = 9999-12-31 00:00 local, sent as UTC). Headers: x-ms-client-user-agent Teams-V2-Desktop,
  x-ms-client-type cdlworker, x-ms-session-id, x-ms-endpoint-id, x-ms-client-version,
  x-ms-client-caller `set-status-note-worker-resolver:DataViewSchemaCdlSetStatusNoteMutation`, x-ms-correlation-id.
- **Clearing a status message**: an empty message gives `{"message": ""}`
  (no expiry).
- **Mentions in a status message**: for each mentioned person with an
  existing 1:1 chat, a RichText/Html message is posted there:
  `<div style="width:60rem;"><strong>Automated message: {me} mentioned {them} in a status message</strong></div><blockquote>{note}</blockquote>`.
- **Who sees it**: the compose box shows a status banner only for pinned
  notes ("Status of {name}: {message}"), and an OOF banner.
- **Sign out** (`nova:me_control_sign_out_button_text` "Sign out") →
  `signOut` command.
- **Pause notifications** (me control `pauseNotificationsControl`,
  async-entry ≈9 634 000; measured on winpc 2026-11-09):
  - The row (bell, filled brand while its menu is open) opens a submenu to
    the flyout's left: 10 minutes, 30 minutes, 1 hour, Today, Custom |
    Notifications settings (settings glyph; only that row leaves room for
    an icon).
  - A choice sends `setPresenceAvailability({availability: "DoNotDisturb",
    expiry: {custom: ISO}})`: now + 10 / 30 / 60 minutes, Today = 23:59:59.999
    local. That is `PUT …/v1/me/forceavailability/` with
    `desiredExpirationTime`, as the status menu's Duration.
  - Paused = DoNotDisturb with an expiry. The presence service gives your
    own expiry in `getpresence` as `forcedAvailability.expiry` (probed
    2026-11-10). So DND set from the status menu with a duration also shows
    as paused, as in Teams.
  - Paused, the row becomes a card (76 in, 234 x 54, #F5F5F5, radius 4,
    padding 8): "Notifications paused" 12/20 semibold, "Until {time}" 10/10
    #424242 (the time today, else "Nov 10, 12:02 AM"). On hover or focus:
    Edit pause duration (edit 16, filled brand on hover; the same menu,
    below and end-aligned) and Resume notifications (dismiss 16), 20 px
    buttons 184 and 206 in. Resume = `setPresenceAvailability(null)`, the
    forceavailability reset.
  - Custom: "Pause notifications until" (600 x 170): Date (Fluent
    DatePicker, M/d/yy, today to a year ahead) and Time (a dropdown of the
    day's 48 half hours, past ones greyed), starting at the next half hour.
    Picking a date keeps the time unless that is past. Save is off while
    the time is past.
- **Set work location** (places control, `places-set-work-location-*`;
  captured on winpc 2026-11-10):
  - The row says "Set work location" (location-add), "In the office"
    (building-checkmark, filled brand) or "Working remotely" (home, filled
    brand). Its aria-label is "Your current work location: {label}".
  - Its menu is 240 wide, centred under the row: "For today" (12/20
    semibold #616161), Office (building) and Remote (home). Once a location
    is set, a divider and Clear work location (delete) follow.
  - Requests: `PUT {ups}/v1/me/workLocation/` with
    `{"location":1,"expirationTime":"<23:59:59.999 local, UTC>"}` (Office),
    `2` (Remote), and `{"location":0}` to clear.
  - Read back from `getpresence` / `v1/me/presence/`: `workLocation:
    {location: "Remote", expiry, isForced, locationSource:
    "ForcedLocation"}`.
  - Teams reads its own location again when the flyout reopens.
- **Status message banner** (the same job, `presence-statusmessage-banner`):
  when your status message or its expiry changes and it is pinned, the
  banner says "Your status message is showing in chat and channels when
  people message or @mention you until {M/d/yyyy h:mm AM}." (no "until"
  for Never). It has no action and is dismissed when the message stops
  being pinned. Banners queue: the newest shows, and dismissing it shows
  the one under it (checked on winpc with a pinned note and a pause).
- **Do not disturb banner** (pre-warm job `presence-donotdisturb-banner`):
  whenever your availability changes to DoNotDisturb, the app banner says
  "Your status is set to do not disturb. You'll only get notifications for
  urgent messages and from your priority contacts." with "Change settings"
  (Settings ▸ Privacy ▸ Manage priority access). It is dismissable and
  dismissed when the availability changes away. Banner: full width, 36,
  #F5F5F5, info 20 filled at 12, text 14/20 at 40, a small secondary
  button and Dismiss (24 x 23.3) 12 from the right.

## Sign-out / stop
- When the worker sync engine stops a strategy (`16708.Ke` →
  `strategy.onStop()`, e.g. on sign-out), `PresenceSyncStrategy.onStop`:
  - cancels the activity debounce and the scenarios;
  - sends `user.activity` **inactive** over Trouter;
  - then sends **DELETE `v1/me/endpoints/{epid}`** (caller
    `presence-sync-strategy:onStop`) and marks the endpoint id released
    locally.
- → TODO: confirm this also runs on app quit, not only on sign-out.

## Do not disturb and notifications (async-apps-notifications 876340; pre-warm jobs `PresenceBlockingSignalSubscription`)
- Your own presence is followed through `presenceUpdateEvent`.
  - On each update, the previous presence block is removed.
  - If availability is **DoNotDisturb or Busy**, a block is added, keyed
    by the **activity**. It is stored in the `NotificationsBlockingCache`
    (module 901028).
  - Joining a meeting with "HideNotificationDuringCallsAndMeetings" on adds
    a `meetingOrCall` block.
- **Toast decision** (`jt`), first match wins:
  1. Silent launch → drop.
  2. "Mute all notifications" → drop non-urgent toasts. Urgent ones are
     dropped too if the mute covers urgent and priority.
  3. **`isUrgent` → show.**
  4. Activity block `Presenting` → drop.
  5. Windows Do Not Disturb (`enableOSDnDSupportForCustomToasts`) → drop.
  6. An incoming call when `!onlyPriorityCallsInDnD` → show. Live it is
     true, so calls fall through.
  7. A `meetingOrCall` block → drop.
  8. Activity block `DoNotDisturb` (user-set DND) → drop.
  9. Otherwise show.
- So DND **drops** toasts, and Presenting drops them too. Busy (InACall)
  does **not** drop toasts.
- **Priority access**:
  - A chat toast's `isUrgent` = `isFromPriorityContact || isUrgent`
    (async-entry 16100 `showMessage` ≈2 149 342). For channels it is
    `isFromPriorityContact`.
  - The message itself is urgent when its activity type is `Priority`
    (worker `d` 30317).
  - `isFromPriorityContact` means: 1:1 chat (or activity type UserContact
    / Mention / Reaction), and the sender is in the priority-contacts list
    (`enablePriorityContactsNotifications`).
  - So urgent messages and priority contacts break through DND and Presenting.
- **While presenting**, a toast that is shown anyway (urgent) is redacted:
  - title "You have a new notification"
    (`toastNotifications:toast_presenting_redacted_content`);
  - no text, and a generic Teams image;
  - this applies only when `enableRedactedNotificationsWhenPresenting` is
    on (live).
- **Sound**: muted when the advanced sound settings are on, the
  "PlayNotificationSoundsWhenBusyOrInMeetings" setting is off, and you are
  presence-blocked (DND or Busy), in a meeting, or in an active call.
  Urgent and priority toasts follow "PlayNotificationSoundsForUrgentAndPriority"
  and use the urgent sound.

## Desktop vs web
- `deviceType` and the user-agent: `Desktop` / `Teams-V2-Desktop` vs `Web` / `Teams-V2-Web`.
- Desktop: active = machine unlocked (`shouldCheckMachineState`).
  - System idle is polled only on desktop (`disableSystemIdlePolling` is
    false only on 49–51).
  - Lock → client Inactive (`idleUpdateOnMachineLock`).
  - Priority contacts are on.
  - Client-state changes never publish.
- Web: active = client Active (Teams window input). With
  `enableWebMachineIdle` (on for 1415/1454), the WebMachineTracker supplies
  the machine state.

## OST status against this spec
- [ ] Endpoint body sends `activityReporting: "Transport"`. OST sends only
  id/activity/availability/deviceType (src/api/presence.rs:122-127).
- [ ] Publish the real state:
  - Busy/InACall in calls;
  - DoNotDisturb/Presenting while sharing;
  - Available/Available on call end and unlock.
  - OST always sends Available (src/api/presence.rs:124-125) and never
    looks at `call_state` (desktop/src/backend.rs:74, 1214, 1752).
- [ ] No periodic endpoint re-PUT. OST re-PUTs every 120 s
  (src/trouter/mod.rs:216, 280-287). Teams PUTs only:
  - on Trouter connect (new epid, or more than 240 s since the last success);
  - on state change;
  - after a 404.
- [ ] Hourly `POST v1/me/reportmyactivity/` `{endpointId, isActive}`. OST
  has none.
- [ ] `user.activity` sent twice on connect (the second after 10 s), once
  on each change, `inactive` on lock and stop; ack timeout 10 s → reconnect.
  OST sends one `active` per connect (src/trouter/mod.rs:202-208).
- [ ] Machine lock/unlock detection (logind / screensaver) driving
  `user.activity` and the unlock publish. OST has none.
- [ ] Headers: `x-ms-client-user-agent: Teams-V2-Desktop`,
  `x-ms-endpoint-id`, `x-ms-client-caller`, `x-ms-correlation-id`. OST sends
  only a bearer token (src/api/presence.rs:103-105, 129-133).
- [ ] Base URL: AFD `https://teams.microsoft.com/ups/<region>/` with
  redirect handling, versus `https://presence.teams.microsoft.com`
  (src/api/presence.rs:83). The non-AFD host works, so this is low priority.
- [ ] Retries: 1.5× backoff from 1 s, up to 3.
- [ ] DELETE `v1/me/endpoints/{epid}` plus `user.activity inactive` on sign-out
  (and probably on quit). OST's shutdown just closes the socket
  (src/trouter/mod.rs:314-317).
- [ ] Forced Offline must send `{"availability":"Offline","activity":"OffWork"}`.
  OST omits the activity (src/api/presence.rs:106-108). Reset with no body
  already matches (src/api/presence.rs:108).
- [ ] Status duration (`desiredExpirationTime`, default Today) and the Duration
  page. OST's menu has statuses and Reset only (desktop/qml/TitleBar.qml:311-318,
  418; tray desktop/qml/Main.qml:145-148).
- [ ] Drop duplicate status requests, and requests within 10 s of a pending
  one. OST sets every click (desktop/src/backend.rs:4274-4290).
- [ ] Set status message dialog:
  - 280 chars;
  - "Show when people message me" via `<pinnednote></pinnednote>`;
  - "Clear status message after", default Never, with the expiry table above;
  - PUT `v1/me/publishnote`;
  - delete = empty message.

  OST has none of it.
- [ ] Compose banner for a pinned status note or OOF of the chat partner.
- [ ] Toast filter with DND/Presenting drop, urgent and priority-contact
  breakthrough, presenting redaction, and busy/meeting sound mute. OST's
  `should_notify` ignores presence (desktop/src/backend.rs:981-994,
  2307-2390).
- [ ] Self-presence watchdog: Away/Offline pushed while active → re-create
  the endpoint after 120 s.
- [ ] CLI `set_presence` uses Graph `setUserPreferredPresence` with wrong
  activities (busy→InACall, dnd→Presenting; src/api/presence.rs:52-79).
  Teams uses `forceavailability`.

## Profile flyout pages, as measured (winpc, 2026-11-06)
These were read from the live client's DOM over read-only CDP. Values are CSS px relative to the 320-wide flyout surface; the devicePixelRatio of 1.5 is factored out.

**Set status message** (`me-control-set-status-message`, 320 × 522)
- Back button: 21 × 21 at (16, 16), ChevronLeft20Regular, colour #424242.
- Title "Set status message" at (53, 17), 14/20 semibold #242424. The UPN is at (53, 37), 12/16 #616161.
- Editor: a CKEditor (`ckeditor`, rich text for @mentions) at (16, 71), 288 × 240.
  - Background #EBEBEB, radius 3, padding 8, text 14/20.
  - It has no border at rest. When focused it gets a 2 px brand bottom border.
  - It is focused when the page opens.
  - Placeholder "Type @ to mention someone in your status" (#616161).
- Counter "0 / 280": 14/20 #616161, its right edge 8 in from the editor's and its top at y 282.
- Checkbox "Show when people message me": a 16 px indicator at (18, 351), radius 2, brand when checked, Checkmark12Filled. Label at (46, 349), 14 #242424.
- Info button: 24 × 24 at (254, 349), Info20Regular #424242.
- "Clear status message after" at (16, 390), 14/20 semibold #424242.
- Trigger (`clearStatusMenuTrigger`): a Fluent Button at (16, 424), 288 × 30.
  - NeutralBackground3, no border, radius 4, padding 5 × 12, 14 regular.
  - ChevronDown20Regular at x 256, colour #242424.
  - Hover NeutralBackground1Hover; pressed NeutralBackground1Pressed.
  - Focus adds a 1 px brand bottom border.
  - Its Menu (288 wide, radio items) opens on hover (`openOnHover`).
- Done: primary, 100 × 32 at (191, 474). Disabled it is #F0F0F0 with #BDBDBD text.
- "Schedule out of office": a link at (16, 478), 14 #5B5FC7.

**Duration** (`me-control-set-availability`, 320 × 273)
- "Back" button: 57 × 21 at (16, 18). Chevron at (17, 19); text "Back" at x 42.7, 14 semibold #424242.
- MenuDivider: (11, 43), 298 × 1, NeutralStroke2.
- "Status" at (16, 61), 14 #242424. Its Dropdown is at (16, 85); "Reset status after" is at (16, 142), 14 #424242; its Dropdown is at (16, 166).
- Both are Fluent **Dropdown, filled-darker**, 288 × 32:
  - At rest: NeutralBackground3 with a transparent 1 px border.
  - Hover: NeutralStroke1Hover with a NeutralStrokeAccessibleHover bottom.
  - Active or focus-within: NeutralStroke1Pressed with a NeutralStrokeAccessiblePressed bottom, plus the `::after` brand underline. That underline is 2 px, scaleX 0→1, taking durationNormal with curveDecelerateMid in and durationUltraFast out.
  - Text 12 in from the border (41 after a 16 px presence icon at 13); chevron 20 (#616161) 11 from the right.
  - The Status dropdown takes initial focus.
- Done: primary, 96 × 32 at (208, 226).
