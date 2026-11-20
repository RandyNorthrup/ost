# Town halls and webinars — spec (TASK-0184, TASK-0073 #2)

Measured 2026-11-17 in Teams on the web as ost-test1 inside OST's web
profile (spatest) on linuxlt, over its DevTools port (DOM, network log with
tokens redacted whole), with one public test town hall ("OST TEST 184 town
hall", organizer ost-test1, nobody invited, not shown in the Events app)
created, published, run and cancelled. Teams on the web refuses town hall
presenters (below), and the Windows PC was in use, so the presenter's side
was read in Teams' desktop bundles (build 26276.x: unified-bar-container-
manager, 527114, calling-app, pluginless, r_data-client-calling, string
tables) and checked live with OST, which joins as Teams desktop does.
Events app basics: docs/spec/events.md.

## 1. Creating them (Events app, Calendar)

- Calendar ▸ New ▾ lists Event, Channel meeting and, under "Organization
  templates", Webinar, Town hall, Virtual appointment and Live Event. On
  the web, Town hall there showed nothing; the Events app's Create event ▸
  Town hall is the path measured.
- **Town hall form** ("New town hall"), differences from Create from
  scratch:
  - Set up experience and options: capacity 1,000 / **3,000** (default) /
    10,000 attendees (View only, with Q&A); **Optimize for large
    audience** on (switch with an info button). On: the tiles are Mic and
    Camera (unavailable, 0.3 opacity, "Selected capacity does not support
    this engagement feature.") and Q&A. Off: capacity 1,000 and the tiles
    Mic, Camera, React, "During event" (chat), Q&A.
  - **Manage what attendees see** (410 wide dropdown: Off, On, On with
    preview), "Control the layout, content, and people seen on screen."
  - **Enable green room** on by default.
  - The panel (relative): capacity dropdown 248 × 30 at 57; the switch at
    266, its label at 322, info at 511; "Attendee participation" at 106,
    tiles 132 × 75 at 142 (8 apart); "Manage what attendees see" 233, its
    text 259, dropdown 282; "Enable green room" 329.
  - All options adds Production tools (Who has control of production
    tools; Manage what attendees see; Enable Green room) and, under
    Copilot and other AI, **Facilitator** ("Takes notes, joins the meeting
    chat, and more using the meeting's spoken language. Available when
    Copilot is enabled.").
- Save asks "Save as a draft and continue?" with "Optimize for large
  audience: On". `POST events` for a town hall differs from a webinar:
  `type "Townhall"`, `commentStreamProperties` all on but
  `useBackroomChatAsMainThread`, `eventCapacityProperties {3000, false}`,
  and in `meetingOptions` no `allowTeamsMeetingReactions` or
  `autoAdmittedUsers`, `allowMeetingChat` null, `attendeeRestrictions
  "DisableAudio,DisableVideo"`, `stagingRoomEnabled` true,
  `attendeeViewModes` null **even with Manage what attendees see On** (the
  meeting then had `attendeeViewModes "HostMode"`). The draft makes a
  Microsoft 365 group (`groupId`).
- **Publish**: the draft card's Publish event (172 × 40) ▸ "Ready to
  publish your event?" ("Invites will be sent to attendees. You can add
  more attendees and share the event after it's published."; "These
  settings can't be changed after publishing": Who can view and join,
  Registration; Cancel, Publish event) ▸ `PATCH events/{id}`
  `{"state":"Published","meetingOptions":null}` ▸ "Success! Your event has
  been published" / "Help your attendees discover it:" with "Show event
  in Events app" (off: `isDiscoverable` false), Copy join details, Copy
  event page link, Copy embed code. The page then shows "Upcoming", Join
  (split: Copy join link, Copy join details) and the chat button, the Q&A
  section (Viva Engage) and Manage apps (Custom Streaming, AI Producer).

## 2. Joining

- Every join answers `conversationType "scheduledTownhall"`,
  `convergedMeetingType "v2.townhall"`, `convergedMeetingMode
  "streaming"` for a town hall.
- **Presenters on the web are refused**: 403, subCode 5131, "Presenter
  had BlockPresenterJoinInEvents client capability and so their townhall
  join was blocked." Teams on the web shows "Join this town hall from the
  Teams app" / "Joining a town hall as a presenter or organizer isn't
  available on the web." (Dismiss). The capability is
  `ClientEndpointCapabilities.blockPresenterJoinInEvents` (16384), which
  OST had copied from the web client; the desktop app doesn't send it, and
  without it OST joins as organizer.
- **Anonymous attendees before the start**: 403, subCode 5134
  ("Anonymous user cannot start the meeting, and lobby is disabled for
  streaming enabled meeting."); Teams on the web: "External participants
  are not permitted to join before the event begins. Please join after
  the event has started." (Dismiss).
- The meeting tells what it is in `meetingDetails.meetingCapability`
  (organizer's join): `forceAttendeeStreaming` true, `stagingRoomEnabled`
  true, `meetingLiveState {phase "staging", seqNum 0}`, `attendeeViewModes
  "HostMode"`, `yammerQNAEnabled` true, `allowTeamsMeetingReactions`
  false, `raiseHands "Disabled"`, `attendeeRestrictions "DisableAv"`,
  `maxEventCapacity` 3000; the conversation offers
  `links.updateMeetingLiveState` and `links.setMeetingLayout`, and an
  `activeModalities.broadcast`.
- Teams' town hall check: `forceAttendeeStreaming` or a
  `scheduledTownhall` conversation; webinars and town halls also by their
  template (webinar `firstparty_d892ef44-003e-480c-9929-07349265a2e2`,
  town hall `firstparty_21f91ef7-6265-4064-b78b-41ab66889d90`).

## 3. The green room and going live (presenters)

From Teams' code (mixin `UOe` and the ubar's `zo` phase helper):
- Phase: `prelive` (green room on, not live), `active` (`meetingLiveState.
  phase` "live"), `ended`. Presenters wait in the green room (connected,
  meeting group "greenGroup"); attendees wait in call state Staging
  ("stagingGroup").
- In the green room the bar's end slot has **Start meeting**
  (`staging-room-start-meeting-ubar`, before Leave; "Start event" only
  with `enableTownhallDelayMessage`, off in shipped clients), for
  organizers and presenters. Disabled while starting: "A presenter already
  started the meeting" ("…event"). The alert "Start the meeting whenever
  you're ready." (info, dismissable).
- Start asks "Start the meeting for everyone?" / "{n} attendees will
  enter the meeting" (Cancel, Start meeting; the town hall wording "Start
  the event for everyone?" / "… will enter and watch the event at a slight
  delay." needs the same flag). Failure: "Unable to start meeting" / "Let's
  try starting the meeting again." (then "Wait and try again later or ask
  another presenter or organizer to start the meeting for you."), Close /
  Try again.
- Going live (Teams' meetingGoLive): publish a user-level `ufd` state
  `{"publishStateUFDType":"stage-curtain","meetingPhase":"live",
  "teamsCallId":…}`, wait 3 s, `POST links.updateMeetingLiveState`
  `{from, meetingLiveState {phase "live", sequenceNumber}, links
  {updateMeetingLiveStateStatus}, operationId}`, remove the curtain.
- Live: **End event** (town halls and webinars; "End meeting" otherwise)
  ▸ "End the event for attendees?" / "This will end the event for all
  attendees and return organizers and presenters to the Green Room." /
  "End event for all attendees"; the same steps with "stage-end-curtain"
  and phase "ended". There is no restart.
- The state pill (VirtualEventsLiveIndicator): "Not started", "Live",
  "Ended", then a divider, people glyph and the attendee count; tooltips
  "# attendees waiting" / "# attendees watching" / "# attendees remain";
  attendees see "Waiting" ("Waiting for the event to start."), "Live",
  "Ended".
- Town halls hide Rooms, Whiteboard, Controls, Report a concern and
  Facilitator; webinars hide Report and Facilitator (keep Rooms).
- Manage what attendees see "On" (`HostMode`): People's spotlight becomes
  **Bring on screen** / **Take off screen** (the spotlight state, content
  `{"isParticipantSpotlighted":true,"isScreenShareSpotlighted":false}`).
  "On with preview" (`AdvancedHostMode`) uses production layouts
  (setMeetingLayout) with a Preview and a Live stage.

## 4. Q&A

The bar's Q&A (YammerQnaButton) where `yammerQNAEnabled`: Viva Engage's
meeting Q&A in the side pane,
`https://web.yammer.com/teamsmeeting/teams-meeting/<base64 {"_type":
"TeamsMeeting","id": base64("0#<thread>#0")}>?client=teams&qnaAppType=native&meetingTenantId=…&callId=…&meetingTemplate=Townhall|Webinar&appSessionId=…`.

## 5. Attendees (streaming)

A town hall's attendees join in streaming mode: the stream is described
by a bot participant's `endpointDetails[].streamInformation.streams[]`
(HLS or UMS URLs, key token and delivery URL, eCDN plugin) and played by
Microsoft's Hydra player. Attendees' bar: indicators (Live), Q&A, React,
captions, More, Camera and Mic (off), Leave; before the start "Welcome to"
/ the title / "This meeting will start shortly"; after the end "The event
has concluded. Thank you for attending."

Measured live (OST as organizer started the town hall, 2026-11-17):
- After Start the service answered `updateMeetingLiveStateStatus`
  `{result {code 0, subCode 5999, "No Error."}, additionalDetail
  {successCount 2}}` and the conversation's `meetingLiveState` became
  `{phase "live", seqNum 1}`; End made it `{phase "ended", seqNum 2}`.
  `streamingModeActive` turned true once live.
- The composition service joins as a bot participant
  (`28:e32c9418-…`, "s04-prdnoamcompsvc", presenter) before the start;
  the town hall recorded automatically (its option) once live.
- ost-test2 (an org attendee, OST's capabilities include
  `supportsStreaming`) joined the live town hall's conversation (200, the
  roster with the composition bot) but its call was never answered: a
  streaming attendee doesn't get a media call.
- The anonymous guest was still refused while live (403, 5134, the same
  "External participants are not permitted to join before the event
  begins." in Teams on the web), so Teams' attendee view wasn't seen.

## 6. Run of Show (TASK-0073 #2)

Run of Show is a third meeting timer (`rosTimer` sections with presenters
and durations) started when a town hall or webinar goes live. Teams gates
it on `enableRunOfShowForTownhalls`, which the shipped configuration turns
on only for local and container builds (Teams' prod configuration, read
2026-11-17), so **Teams doesn't show Run of Show in this tenant**: the
town hall's form and All options have no Run of Show setting. Teams'
desktop window couldn't be watched going live (the Windows PC was busy),
so that last step is from the configuration, not seen.

## 7. Measured live in Teams desktop (TASK-0217, 2026-11-18)

Teams desktop on winpc (ost-test1, build 26304) over its DevTools port
(DOM boxes and styles, network log with tokens redacted whole), with two
test town halls ("OST TEST 217 town hall", organizer OST Test 2 in OST,
attendee ost-test1; "OST TEST 217 town hall 2", organizer ost-test1 in
Teams, attendee OST Test 2 in OST), both cancelled afterwards. The call
window's stage was never captured.

### The attendee's stream
- Teams' calling stack (pluginless `handleRosterParticipant`): the join is
  an ordinary meeting join, but the service never answers the call. The
  roster puts our endpoint in a `stream` modality (`streamLobby` before
  the start, in Teams' code) and Teams switches to streaming mode
  (`configureStreamingMode`: call mode 2, connected, media and pending
  call setup dropped, call end subCode DowngradeToStreamingClient).
  OST's attendee join saw `stream` already in the join response.
- The composition service is a bot participant (`28:e32c9418-…`,
  "s04-prdnoamcompsvc") whose endpoint carries `streamInformation.
  streams[]`: `urls`, `isPrimary`, `deliveryPipelineType` in words ("Middle
  Lane HLS Network", "Middle Lane ULL Network", "Azure Media Service";
  Teams' `gV` maps them to MiddleLaneHttpLiveStreaming /
  MiddleLaneUltraLowLatency / AMS), `decryptionKey {id, value}`,
  `setKeyAuthorizationCookieUri`, `keyAuthorizationToken`, `setCookieUrl`,
  `sdn`, `transcription`. They appear once the event is live.
- Teams' pick (`pn`, prod configuration): ULL only with
  `useULLPlayerWithILiveStreamForStreaming` (local builds), else HLS
  (`useHttpLiveStreamingPlayerForStreaming` true), else AMS; the primary
  stream and an alternate with other URLs.
- The player: an iframe (`/v2/streaming-container.html`) loading
  Microsoft's Hydra HLS player (`s01-ml-player/4.26315.1/
  hydra_player_hls_bundle.js`). It fetches `…prod.ml.cdn.office.net/v1/
  fileserver/{id}/{stream}/media.m3u8` (fMP4: `video33.m3u8`,
  `video34.m3u8`, `video35.m3u8`, `audio.m3u8`, `*_init.m4s`,
  `*_0047.m4s`), no cookies; the key from the playlist's key URI
  (`kd.public-teams.keys.ml.teams.microsoft.com/v3/hlskeydelivery/
  {stream}/get-key/…`) with the stream's `keyAuthorizationToken` as the
  bare `Authorization` header. `setKeyAuthorizationCookieUri` wasn't
  called.
- OST plays it natively: a loopback server hands the playlists (rewritten
  to come back through it), segments and keys (with the token) to Qt
  Multimedia's FFmpeg HLS demuxer.
- Hidden from the stage and People by Teams' `blacklistedBots` (ECS
  Calling, prod default list, which names the composition service and the
  call recorder) and an endpoint's `botData.hiddenParticipant`
  (useFilterBlacklistedBots).

### The attendee's window (streamingClient layout)
- The prod `ubarLayoutOverrides` entry `streamingClient` (available:
  CallDurationIndicator, Mic, Video, Raise, React, apps, Q&A, Chat, Leave,
  Resume, Audio/Device settings, Captions, AI interpretation, More,
  annotations, the live indicator, Hide controls; Captions and More moved
  to the middle slot).
- Before the start: the bar is the state pill "WAITING" (#EBEBEB,
  #616161, "Pre-live state."), Q&A, More, Leave, centred; the stage
  (#F5F5F5) says "The event isn't live right now." (24/32 bold #252423).
  No title, duration or shield.
- Live: "LIVE" (#D13438, white), Q&A, Captions, More, Leave; the player
  fills the stage (0, 92, 1280 x 588) with its controls along the
  bottom: a progress bar (8, 616.7, 1264 x 20), Pause (Alt+K), Skip back
  10 s, Skip forward 10 s (Alt+L), Mute (Alt+M), the position (14 px
  white) and Full screen (Alt+Enter).
- Ended: "ENDED" (#EBEBEB); the player stays. More holds only Device
  settings.
- The pill: 21.67 tall, radius 10, padding 0 8, 11.67 px uppercase.

### Presenters
- Pre-join of a town hall organizer: Join now is a split button
  (`prejoin-join-button-event-etm`, 96 + 26.67) whose menu (141 wide, 14
  px, no glyphs) has "Join as Organizer" ("Join as Presenter") and
  "Preview as Attendee". Preview joins with
  `participationPreferences {requestedEndpointMeetingRoles ["attendee"]}`
  (Teams' joinEventAsAttendee).
- Green room: the pill "NOT STARTED" on #FDE300 (#242424) with a divider,
  the eye glyph and the attendee count ("Pre-live state. 0 people have
  joined"), then the duration; the end slot's **Start event**
  (`staging-room-start-meeting-ubar`, PlayCircle filled glyph, an
  ordinary bar button 53.4 wide) before Leave; the alerts "Recording and
  transcription will begin when the meeting starts." and "Start the
  meeting whenever you're ready."; with Manage what attendees see on, the
  "Manage screen" panel (240 wide: Add Videos, "Attendees can still hear
  your audio when you're off screen.", All / Live / People / Content,
  the off-screen tiles with their Stage presence toggles) beside the
  stage ("Bring presenters on screen and share content that you want
  attendees to see.").
- `enableTownhallDelayMessage` is on: "Start the event for everyone?" /
  "1 attendee will enter and watch the event at a slight delay." (Cancel,
  Start event; 600 wide); the stage says "Starting..." and Start greys
  out (#BDBDBD).
- Live: "LIVE | (eye) 1" ("Live state. 1 attendee watching at a delay"),
  the recording indicator, **End event** (DismissCircle, 49.3 wide).

### Events app
- Publish ▸ "Success! Your event has been published" (800 x 454): a
  preview of the card (369 x 309, radius 24; title, date, By, Online,
  Join, copy link) with "Here's what attendees will see." (10 px); "Show
  event in Events app" / "Attendees with access can view" with a switch
  (on for the private test event: the service's `isDiscoverable`); Copy
  join details, Copy event page link, Copy embed code (town halls: Teams'
  `<iframe src="https://teams.microsoft.com/convene/townhall?eventId=…"
  width="1280" height="720" …>`). The switch sends `PATCH events/{id}
  {"isDiscoverable": …}` with the event's eTag (If-Match).
- The published event's page: Edit details, Share, More options; tabs
  Overview, People & emails, Insights, Highlights; Join (split, Join
  menu) and Chat with participants.
- Cards: a published event shows "Live" (#D13438, record glyph 10, 10/600
  white, 40 x 16) from start to end and "in N mins" (#E8EBFA, brand,
  clock 12, rounded down to 5, at least 5) in the hour before; the date
  follows the badge; Join (64 x 23) and Copy event page link replace Edit
  from 5 minutes before the start.
- Calendar ▸ New ▾ (174 wide): Event, Channel meeting, then
  "Organization templates" (12/600 #616161): Webinar (Fluent glyph
  U+E416, a board with a person), Town hall (MegaphoneLoud), Virtual
  appointment, Live Event.

## 8. Round 2 in Teams desktop (TASK-0217, 2026-11-19)

Measured on winpc (ost-test1, build 26304) with "OST TEST 217 town hall
preview" (organizer ost-test1 in Teams) and "OST TEST 217 virtual
appointment" (guest OST Test 2), both deleted afterwards.

### Going live and published states
- Teams' calling stack posts a published state's content as an object:
  pluginless publishStateAsync parses the state's JSON and its payload
  builder sends `publishedState {content: <object>, level, stateType,
  sequenceNumber}` (and endpoint states the same way). OST sent the
  curtain (`stage-curtain`) and the spotlight (Bring on screen) as JSON
  strings; both go as objects now.
- `updateMeetingLiveState`: `{from {id, endpointId, participantId,
  languageId, displayName}, meetingLiveState {phase, sequenceNumber},
  links {updateMeetingLiveStateStatus}, operationId}`, the sequence
  number being the meeting's `meetingCapability.meetingLiveState.seqNum`
  (handleMeetingDetailsChanged) — as OST sends it.

### Joining as organizer without dropping attendees
- A town hall's conversation ends for everyone once its last non-hidden
  participant leaves: streaming attendees got `conversation/
  conversationEnd` code 0, subCode 5020, "This conversation has ended as
  there are no non-hidden participants in the incoming roster." (Teams
  only logs it: CallEndDiagnosticsWithNoInnerParticipant). OST's
  organizer hit it by withdrawing its pre-join preheat when Join now came
  before the preheat was answered (and again when the pre-join window
  closed), then joining afresh: the preheat had been the only presenter.
- Teams never leaves and rejoins: Join now promotes the preheated call
  (disablePreheat). OST now waits for a preheat still being placed and
  joins that call; closing the window doesn't withdraw a preheat Join now
  waits for.
- Checked live 2026-11-19 ("OST TEST 217 town hall B2"): OST Test 2
  organized in OST, ost-test1 watched in Teams desktop; Teams' attendee
  stayed WAITING while OST joined (preheated), went LIVE with the player
  running when OST started the event, then ENDED.

### Manage what attendees see
- The webinar form has no "Manage what attendees see" here (neither the
  quick setup nor All options ▸ Production tools: Who has control of
  production tools, Enable Green room). Webinars get it only through the
  meeting's own options.
- The town hall form's dropdown (Off / On / On with preview, the form's
  `productionStudioMode` Off / Simple / Advanced) isn't sent: `POST
  events` carries `attendeeViewModes` null and no `productionStudioMode`,
  Publish `{"state":"Published","meetingOptions":null}`. The town hall
  came out `HostMode` (On) with "On with preview" picked.
- In the meeting, More ▸ Settings ▸ Meeting options ▸ Production tools
  has "Manage what attendees see" ("Choose if you'd like organizers and
  presenters to manage the content and people attendees see on their
  screens. Only people you've selected in the setting above can manage
  the screen.") as three radios: Off (`Default`), On (`HostMode`), On
  with preview (`AdvancedHostMode`), saved with the meeting options
  (`AttendeeViewModes`).

### The Manage screen panel (HostMode, organizers and presenters)
- The stage (2.7, 94.7, 1274.7 x 582.7) splits: the panel 240 wide on the
  left, the managed stage (242.7, 1034.7 wide) on the right showing only
  who is on screen; with nobody there it says "Bring presenters on screen
  and share content that you want attendees to see." (18/700 #252423 on
  #F5F5F5, centred).
- The panel: a 60 tall header ("Manage screen" 14/600 #252423 at 20, 20;
  an info button 16 at 121; Add Videos, a 32 x 32 button with a 20 glyph
  at 196, 14), a divider at 59.3, "Attendees can still hear your audio
  when you're off screen." (12/14 #424242 at 20, 66, 200 wide), the pills
  All / Live / People / Content (24 tall, radius full, at 20, 102; the
  chosen one #5B5FC7 with 12/600 white, the others 12/400 #424242), then
  the organizers' and presenters' tiles (236 x 131 at 2, 134.6; your own
  with your avatar and name tag) with their Stage presence switch at the
  top right ("Stage presence: Off stage"). The Start the meeting alert
  wasn't shown with it; "Recording and transcription will begin when the
  meeting starts." was.
- The form's preview of On with preview (the town hall form): Preview
  (yellow edge) and Live (red edge) stages, Customize screen and Send
  live (#FDE300), "Manage screen and audio", End event (#FDE300); an
  Attendee view / Your view switch under it.

### A webinar's attendee before the start
- Teams joins the call (attendee, green room on, not live): the bar has
  the "Not started" pill (11.67 #616161), the duration, Mic, Camera,
  Share, React, Chat, People, Copilot, Q&A, More, Leave; the stage says
  "Welcome to" (14/400 #616161 at 336), the title (20/700/28 #242424 at
  372) and "This meeting will start shortly" (14/400 #616161 at 416),
  with the alert "Recording and transcription will begin when the
  meeting starts".
- An invited attendee of a webinar with registration joins straight from
  Calendar's Join (no Register step).

### Calendar ▸ New ▸ Virtual appointment and Live Event
- **Virtual appointment** opens Teams' "New meeting" window (1226 x 713)
  headed "Virtual appointment" (Details, Scheduling Assistant, Send): a
  notice bar ("External guests will receive a tailored invitation for
  this scheduled online meeting. They will join from a mobile or web
  browser and experience a virtual lobby before the appointment begins.
  Learn more"), Add title, "External guest name *" and "Email *" (316 x
  31 each) with "+ Add additional external guest", the times, Does not
  repeat, "Add attendees within my organization" (+ Optional), Add
  location, the editor; Options: Who can present "Only organizers and
  co-organizers", Record and transcribe automatically Off, Meeting chat
  "In-meeting only", More options. Opening it makes the Teams meeting
  (`privateMeeting/schedulingService/create`). Send: `POST {mt}/v2.0/me/
  calendars/default/events?isOnlineMeeting=true&shouldDecryptData=true`
  with the usual calendarEvent and schedulingServiceEvent, but
  `meetingTemplateId "firstparty_e514e598-fba6-4e1f-b8b3-138dd3bca748"`,
  `isAppointment` false, only the organizer in `attendees`, and
  `virtualAppointmentInfo {appointmentClients [{displayName,
  emailAddress}], eTag "", isSmsEligible false, settings
  {allowClientToJoinUsingBrowser true, notifications [], organizerLocale
  "en-us"}}`.
- **Live Event** shows "Teams Live Events is Retiring" (Fluent v8 dialog,
  340 x 209, radius 2; title 20/400 #242424 padded 16 46 20 24; "Teams
  Live Events is retiring. Please transition to Teams town hall to get
  the improved experience for large digital and hybrid events at scale.
  For more information, Learn more." 14/400 #616161 in 292; "Create town
  hall" primary 145 x 32 and "Continue" 99 x 32, 8 apart, radius 2).
  Create town hall opens the town hall form; Continue opens a 946 x 713
  "Microsoft Teams" window: "New live event" (21/700 #616161 at 30), the
  Prohibited glyph (regular, 80, #616161) centred, "Teams live events is
  retiring, please use Teams town halls for your large digital and
  hybrid events" (14/700, the link 14/400 #4F52B2 to adoption.microsoft.
  com …/town-halls/), and Close (96 x 32, 600, #D1D1D1 edge) at the
  bottom left.

## 9. Round 3 in Teams desktop (TASK-0217, 2026-11-19)

Measured on winpc (ost-test1, build 26304) with "OST TEST 217 r3 town
hall" (organizer ost-test1), "OST TEST 217 r3 town hall B" (organizer OST
Test 2 in OST, presenters OST Test 3 and ost-test1) and "OST TEST 217 r3
webinar reg" (organizer OST Test 2, organization-wide, registration on).

### Manage what attendees see during a meeting
- `ManagedMode` saved while the meeting runs (OST's meeting options or
  Teams' own Meeting options ▸ Apply) doesn't reach the running
  conversation's `attendeeViewModes`; the next conversation (everyone
  left, then joining again) has it.
- A webinar organized by OST Test 2 has no `ManagedMode` option at all
  (its options stop at ProducerOption); town halls have it.

### "On with preview": Send live
- The preview is the producer's own (Teams keeps it in its local
  previewProductionStudioLayout cache): "Add to preview" sends nothing.
- Send live: the production studio's setProductionLayout ▸
  convertLayoutToPayload, then calling-electron's setMeetingLayout hands
  SlimCore `meetingLayoutJson` (the layoutDetails as JSON) and the
  operation id; SlimCore's CSetMeetingLayoutOperation posts it to the
  conversation's `setMeetingLayout` link (status callback
  `conversation/setMeetingLayoutStatus/`). Teams' pluginless stack (the
  same protocol in JS, aG) posts `{from {id, endpointId, participantId,
  languageId, displayName}, layoutDetails, operationId, sequenceNumber
  (meetingLayoutSequenceNumber), links {setMeetingLayoutStatus}}`.
- The layoutDetails Teams desktop sent (CDP logpoint): `{layout {id
  "<teamsCallId>_Preview", participants [{id <mri>, participantId,
  endpointId, modality "VIDEO", isRTMPInVideo false, state null}],
  nameTag {isEnabled true}, kind "CLASSIC", kindDetails null, background
  null, action "put"}, sequenceNumber}`, the sequence number being the
  conversation's (0, then 1 …). An empty preview sent live clears the
  live screen.
- Every participant then gets `conversationUpdate` `layoutDetails`
  `{lastNonScreenshareLayoutKind, lastSideBySideLayoutKind, lastUpdatedBy,
  layout {action, kind, lastNonScreenshareLayoutKind ("CLASSIC"),
  lastScreenshareLayoutKind ("SIDEBYSIDE"), …Type, lastUpdatedById,
  nameTag, operationId, participants [{endpointId, id, isOnStage true,
  isRTMPInVideo false, modality, participantId}], resolution {1280 x
  720}, sequenceNumber}, sequenceNumber + 1}` (null before anyone sent
  one; kind "NONE" at first). OST Test 2 got it about a second after
  Teams pressed Send live.
- Kinds: PANELIST, CLASSIC, SPEAKER, GALLERY, SIDEBYSIDE, STACKED,
  CONTENTONLY, CONTENTSPEAKERFOCUSED (NONE reads as CLASSIC); with a
  screen share among the sources Teams picks SIDEBYSIDE.
- The producer's view (1280 x 680): Preview and Live stages 402.9 x 226.6
  (16:9, the top part's height less 132.1), 32 apart about the middle,
  each in a 2.67 #FDE300 frame (Live too before the start), the titles
  16/700 12 above; Send live (96 x 31.3, #FDE300, 0.67 #D1D1D1 edge,
  14/600 #242424) 24 under the Preview's right edge; on the Live title
  row, right-aligned, "Last updated by **name**" (13/400, "you" for
  yourself). The Manage screen strip: a 60 tall header (0.67 #E0E0E0 top
  edge), tiles 273 x 152 on a 277.3 pitch with an "Add to preview" /
  "Remove from preview" switch. Three sources on a sub stage: two 196.7
  x 110.6 tiles side by side, the third centred under them.
- Two people on the HostMode managed stage (1034.7 x 582.7) sit side by
  side at 517.3 x 291.
- The green room's alert for an auto-recorded event is "Recording and
  transcription will begin when the meeting starts." (Teams' recording
  UFD RecordingAndTranscriptWaitingForMeetingLive, 318.7 wide).

### Webinar registration
- OST's "Show event in Events app" sent `{"isDiscoverable": on}`: the
  service ignores it. Teams' updateVirtualEvent converter puts the flag
  in `access`: `PATCH events/{id}` `{"access": {"isDiscoverable": on},
  "meetingOptions": null}`. With that, the organization-wide webinar
  appeared at once in ost-test1's Discover "Upcoming events in your org"
  (the r2 event never did because the flag never changed).
- Discover's card for an event with registration: Register (84 x 23.3,
  outlined #D1D1D1, the calendar glyph, 12/400) and Copy event page link;
  registered, "Registered ▾" (117.4, calendar-checkmark) whose menu has
  Unregister. The card's state is `requesterPropertiesBySession.
  {session}.registrationStatus`; `registrationInfo` holds the questions
  and termsOfUseUrl.
- Register opens a 600 wide dialog (radius 8, padding 24): the title
  20/600, the date 14 ("Thursday, November 19, 2026, 6:00 AM - 7:00 AM"),
  a divider, "Registration Information" 14/600, First name / Last name
  (186.7 x 30.7) and Email (549.3) filled from your profile and disabled,
  red asterisks, a divider, "I have read and agree to the Microsoft Event
  Terms and Conditions *" (go.microsoft.com/fwlink/?linkid=2210903),
  Cancel and Register (96 x 31.3). Teams first reads
  `GET events/{id}/users/{oid}/registration`.
- Register: `POST {teamsevents}/events/{id}/attendee/register` (the id
  URL-encoded) `{"language":"en-us","timeZoneDetails":{"ianaTimeZone":
  "America/Los_Angeles","windowsTimeZone":"America/Los_Angeles",
  "localizedTimeZoneString":"GMT-08:00 America/Los_Angeles","utcOffset":
  -480,"timeZone":"America/Los_Angeles"},"firstName":"OST","lastName":
  "Test 1","email":"ost-test1@scnetsolutions.com","answers":[],
  "hasAcceptedTermsOfUse":null}` → `{registrationId, status
  "Registered", meetingJoinUrl (with prid), …}`; the dialog turns into
  "You're registered!" (Teams' 192 illustration, 20/600) and "We sent a
  confirmation email to …", with an "Event Registered" toast.
- Unregister ▸ "Cancel your registration?" (600 x 168: "You'll be
  removed from the event if you cancel. You can register again later if
  you change your mind.", Stay registered, Cancel registration): `POST
  events/{id}/attendees/{registrationId}/cancel`, no body, 204.

### The pre-join's Join as menu
- Items 140.9 x 32, 2 apart, 14/400 #424242 6 in, starting 5 right of
  Join now's left edge and 4.5 under it; the chevron part turns #4F52B2
  while the menu is open.

## 10. Leftovers (TASK-0227, read in Teams' bundles 2026-11-19)

### The green room's recording notice
- The call recorder joins an auto-recorded event's green room with its
  processing modes `recording` and `realTimeTranscript` in the state
  "WaitingForMeetingLive"; Teams' recording alerts (527114) then show
  RecordingAndTranscriptWaitingForMeetingLive "Recording and transcription
  will begin when the meeting starts" (only the transcript waiting:
  "Transcription will begin when the meeting starts"; only the recording:
  "Recording will begin when the meeting starts"), a dismissable warning
  with the record glyph (Teams' alert icon map 263640). Teams' alert
  service shows one alert: it covers "Start the meeting whenever you're
  ready." for organizers and presenters, and shows on a webinar
  attendee's waiting screen too. Measured: 318.7 x 62 at the stage's top,
  the glyph 12 in and centred, the text 14/20 #616161 40 in, 11 down,
  252.7 wide (two lines), the 20 px dismiss glyph 30.1 from the end.

### Registration forms with questions
- The organizer's Registration form (events-scheduling-form): predefined
  fields (Address, City, State, ZIP/Post code, Country/Region, Industry,
  Job title, Organization; type Text, category Predefined, `internalName`)
  and custom questions (Text, Choice = SingleChoice, or MultiChoice with
  "Multiple select", Boolean; category UserCreated), each with Required.
  New questions go without an id (the form's "predefined-…" / "custom-…"
  ids are dropped); stored in `registrationInfo.questions` (POST events,
  or PATCH events/{id}/registration), each `{id, category, type,
  displayText, isRequired, order, choices, internalName,
  isCheckedByDefault}`; types also Note and PromoEmailConsent.
- The attendee's Register dialog (meet-app) lists them after Email, 12
  below, 16 apart, by `order`: Fluent fields labelled with the question
  (a predefined field's own label) and a red "*" when required. Text: an
  input (255 characters, "Max number of characters reached."). Note: a
  4-row text area (1,000). SingleChoice: radios. MultiChoice: checkboxes 8
  apart (required: at least one). Boolean: a checkbox with the question
  beside it (ticked when `isCheckedByDefault`). PromoEmailConsent: a
  checkbox 8 lower, never required. Register checks them ("This field is
  required.", 12/16 red with the 12 px error glyph under the field) and
  sends `answers` `[{Id, Answer}]` (Boolean as true/false, MultiChoice a
  list, the rest text; unset multiple choices left out), with
  `hasAcceptedTermsOfUse` only when the organizer set terms of use. A
  failed Register shows the error bar "Couldn't complete request." / "Try
  again in a moment.". The dialog scrolls within 90% of the window.
- The organizer reads the answers in the registrations (`events/{id}/
  attendees?status=…`: `answers [{id, displayName, answer}]`; a single
  choice comes back as a one-item list).

### "By" on attendees' cards
- meet-app's card (Or / dr): organizers see "Organizer" / "Co-organizer";
  everyone else "By" the session's presenters: those without lobby bypass,
  then those with it; hidden ones, rooms and nameless ones left out; an
  external presenter whose name is an email shows as "Guest Speaker".
  Two names, then "+N" ("By {{presenters}} +{{count}}"), with all of them
  in the tooltip when there are more than one. With no presenters the
  event's owner ("By OST Test 2").

## OST status (see the tasks' notes for the live checks)

- [x] Events: the Town hall template's form (capacity, large audience,
  tiles, Manage what attendees see, green room), its draft as Teams sends
  it, Publish with Teams' dialogs (People & emails read first), Upcoming,
  Join (pre-join) with Copy join link / details, and the event chat.
- [x] Joining a town hall as organizer or presenter (the desktop's
  capabilities).
- [x] The green room: Start event / Start meeting (Teams' town hall
  wording and the delay message), End event, the state pill as measured
  (§7), the alert, the bar rules for town halls and webinars, Q&A, Bring
  on screen / Take off screen.
- [x] Town hall attendees (TASK-0217): streaming mode from the roster,
  the composition service's HLS stream played natively (Qt Multimedia
  through OST's loopback server, the key with its token), the
  streamingClient bar (Waiting / Live / Ended, Q&A, Captions, More with
  Device settings, Leave), "The event isn't live right now.", leaving
  through the conversation's leave link; Teams' blacklistedBots hide the
  composition service from the stage and People.
- [x] Preview as Attendee and the pre-join's Join as Organizer / Presenter
  split; Calendar ▸ New ▸ Webinar / Town hall (the Events form with that
  template); the published dialog's card preview, Show event in Events
  app and Copy embed code; the cards' Live and "in N mins" badges and
  their Join.
- [x] An attendee's staging screen ("Welcome to" / title / "This meeting
  will start shortly", and the end text) where the call connects (webinar
  attendees); the presenters' alert after the end.
- [x] Round 2 (TASK-0217, §8): the organizer's join reuses its preheated
  call (attendees stay); published states' contents go as objects; the
  Manage screen panel (HostMode); Meeting options ▸ Production tools ▸
  Manage what attendees see (ManagedMode: Off / On / On with preview);
  Calendar ▸ New ▸ Virtual appointment (Teams' template, external guests)
  and Live Event (the retirement dialog and window); the webinar
  attendee's waiting screen as measured; your registration read
  (`events/{id}/users/{oid}/registration`).
- [x] Round 3 (TASK-0217, §9): "On with preview" (Preview and Live
  stages, Add to preview, Send live through the conversation's
  setMeetingLayout as Teams sends it, the live layout from
  layoutDetails, "Last updated by", the Manage screen strip; webinar
  attendees see only the live layout); Show event in Events app sent as
  Teams does; Discover's Register / Registered / Unregister with Teams'
  dialogs; the Join as menu's geometry; two people side by side on the
  managed stage.
- [x] TASK-0227 (§10): the green room's recording alert, registration
  forms with questions, "By" on attendees' cards.
- [ ] Open: the player's own controls and live stream captions.
