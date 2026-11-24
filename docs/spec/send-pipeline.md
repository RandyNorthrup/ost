# Chat send pipeline: optimistic message, retries, offline queue, failure UI — Teams desktop behaviour (spec)

Source: the Teams client itself (same build and method as
`messages-and-composer.md`). Module ids marked **W** come from the data-layer web
worker (`precompiled-web-worker-inner_*.worker.js`), which has its own module-id
space. Ids without a mark are UI bundle modules. Strings are en-us, decoded with
`tools/tstr.py`. "Live" values come from `settings-live*.json` (winpc, ost-test1).
"Prod default" values come from `config-prod-*.js` and are used when the live
dump does not contain the key (for example, the `chatService` category was not
dumped).

This extends §6, §7 and §18 of `messages-and-composer.md`. One correction to §6
there: a failed send does **not** get an Edit button (see §6 below).

---

## Components (module index)
| area | module(s) |
|---|---|
| Composer send entry: prepared message, client-lie post, mutation choice | 656562 (`sendMessage` epic), 955743 `sj` (prepared `SendMessageInput`), 114068 (`dt`/`Vt` mutate, `S` OAM options, `ht` mutation choice, `xt` legacy retry) |
| clientMessageId generator | 847725 `H1` → 770328 `sN` → 130933 `yT` |
| OAM queue id / action id | 689904 (`queue_…`), 577266 (`send_…`) |
| Worker `sendMessage` resolver, lie construction | **W** inner_d 68245 (`xn`, `Sr`, `vt`, `dn`, `ns`, `Ko`), status map **W** services_i 87208 `Ox` |
| Offline action middleware (persist/replay) | **W** inner_d 99317 (`offlineAction`), manager **W** inner_b class `OfflineActionsManager`, replay **W** inner_c 6814 (`OfflineActionsSyncStrategy`) |
| Send workflow | **W** inner_c class `EI` (`MessageSendWorkflow`), job **W** 68143 (`MessageSendJob`), base timeout **W** 44436 |
| Error classification | **W** inner_c 16163 (`E2` error code, `Df` sendPipelineStatus), HTTP enum **W** 88102 |
| HTTP request and transport retry policy | **W** services_i 34565 (`do` POST builder), 66704 (`P` retry policy, `postMessageToConversation`), 6209 (Retry-After) |
| Failure text / retry tooltip keys | 533020 (`v`, `u`), 947361 (`mx`), 96509 (`aH` isLie, `HO`, `En`) |
| Failure UI in the message | 318259 (`Rd` status line, `Td` error title, `bc` status icon, `getFailedActionMenuProps`, `Ug` retry), 317519 (Retry/Edit buttons), 862660 + 377517 (Delete), 299320 (slot layout) |

---

## 1. Message status lifecycle

Worker state enum (**W** 18823 `rI`) and the GraphQL `MessageStatus` the UI sees
(**W** 87208 `Ox`):

| worker `state` | value | GraphQL `status` | meaning |
|---|---|---|---|
| Sending | 0 | `Sending` | lie created, POST not finished |
| Delivered | 1 | `Delivered` | POST succeeded; server id in place |
| Received | 2 | `Delivered` | (incoming messages) |
| Error | 3 | `Error` | terminal failure; shows failed UI |
| Deleted | 4 | `Delivered` | — |
| Retrying | 5 | `Retrying` | retryable failure; queued for replay |

`Undeliverable` exists in the GraphQL enum. For a chat message it is set only
client-side, by the async file-upload watcher, when an attachment upload fails
(`markOptimisticMessageUndeliverable(..., "Undeliverable", "FILE_UPLOAD_FAILED")`).
The UI treats it like `Error` (96509 `HO`: `Error || Undeliverable`). Pending
means `Sending || Retrying` (96509 `En`).

### Transitions (live flags: `enableAutoSendV2` true, `enableAutoEditV2` true)
| from → to | trigger (module) |
|---|---|
| (none) → **Sending** | resolver builds the lie (`vt`, `state: Sending`). The workflow writes it to the local reply-chain store as `PostNewClientLie` (**W** `EI.startImplementation`) |
| Sending → **Delivered** | POST returns 2xx with a `Location` header. `setSuccessMessageProps`: `state=Delivered`, `id`=server id, `version`=server id, `originalarrivaltime`=server OAT. Lie re-posted as `ResolveNewClientLie` |
| Sending → **Retrying** | POST fails with a retryable error **and** `updateMessageStatusOnFailure` is false (see §2). Lie re-posted with `state=Retrying` plus `sendPipelineStatus`. The action stays at the head of its OAM queue |
| Sending/Retrying → **Error** | terminal error, **or** `updateMessageStatusOnFailure` true (final OAM replay, scheduled send, or auto-send off). Lie re-posted as `SendMessageError` with `sendPipelineStatus` |
| Retrying → Sending → … | OAM replay (startup, reconnect, Trouter reconnect, 10-min interval; §3) |
| Error → Sending → … | user presses **Retry** (§5) |
| Error/Retrying → (removed) | user presses **Delete** (§5) |

`updateMessageStatusOnFailure` (**W** 68245 `Sr`):
`(!autoSendV2 && (postType || replyChainId)) || scheduledSendTime || isFinalRetry || !autoSendV2`.
With auto-send on, a first attempt or an ordinary replay therefore never goes
straight to Error on a retryable failure.

---

## 2. Retry policy

There are three layers.

### 2a. Transport retries inside one POST (auto-send on)
`postMessageToConversation` uses `_transportWithRetryOnceOnOffline` when
`enableAutoSendV2`, otherwise `_transportWithNoRetry` (**W** 66704). Its policy is
`P(coreSettings, undefined, undefined, isSendMessage=true)`. The retry loop
(**W** services_i `h`) calls `shouldRetry(attempt, status, counts, headers)` with
attempt = 0, 1, 2, …

| setting (`chatService`) | prod default | used as |
|---|---|---|
| `maxRetryCount` | 4 | retry only while `attempt < 4` → at most **5 attempts** |
| `minRetryIntervalMs` | 1000 | base delay |
| `exponentialDelayFactor` | 2 | delay = `min(maxRetryTimeMs, 1000 × 2^attempt)` → **1 s, 2 s, 4 s, 8 s** |
| `maxRetryTimeMs` | 300000 | delay cap |
| `maxEndpointFallbackCount` | 3 | 502+503 combined count ≤ 3 |
| (hard-coded) `maxNotAuthorizedCount` | 1 | 401 retried once (after token refresh) |
| `maxRetryCountForSendMessageOfflineResponse` | 7 | network failure count limit (moot under the 4-retry cap) |
| `enableChatServiceSendMessageExponentialBackoffRejectHttpError` | true | network failures also use exponential delay (otherwise fixed `retryIntervalForOffline` 25000 ms) |

`shouldRetry` per status:

| status | retried? |
|---|---|
| no response (`FailedToFetch` / `RejectHttpError`) | yes |
| 429 | yes |
| 502, 503 | while their combined count ≤ 3 |
| 401 | while count ≤ 1 |
| 412 | unless the request had `If-Match` |
| 404 | no (the NotFound policy is not passed for send) |
| any other 500–599 | yes |
| any other 4xx (400, 403, 408, 413, 455…) | no |
| any status with `Retry-After` > 300 s | no (6209 `__`) |

`Retry-After` (seconds × 1000) wins when it is larger than the computed delay:
`max(minDelayForRetry || 0, max(retryAfter, delay))`.

With auto-send **off**, the composer instead wraps the whole mutation
(114068 `xt` = 200657 `Z`): **3 attempts, fixed 30 s backoff, 60 s window**, retried
only for 429, 401, 500, 502, 503, 504, 507, 509, 511, 599.

### 2b. Workflow error classification (after transport gives up)
`MessageSendJob` (**W** 68143) rejects with `TerminalError` for **455
THREAD_READ_ONLY / 456 THREAD_BLOCKED**, otherwise `Unknown`.
`MessageSendWorkflow.handleError` then computes the code with **W** 16163 `E2`:

| server response | code | result |
|---|---|---|
| none (network) | `Unknown` (or the transport code `RejectHttpError`) | retryable → **Retrying** |
| 2xx | `Empty` | — |
| 429 | `Throttled` | retryable → Retrying; the OAM queue is flagged as throttled (skips the next interval replay) |
| 401, 412, 500, 502, 503, 504, 507, 509, 511, 599 | unchanged (non-terminal) | retryable → Retrying |
| anything else (400, 403, 404, 408, 413, 455, 456, 501…) | `TerminalError` | **Error** at once |

A chat containing a bot that cannot use the offline queue also turns the error
terminal (`Iu`). The whole workflow has a timeout of
`defaultWorkflowTimeoutSeconds` (prod 180 s). The job uses the same value.

### 2c. `sendPipelineStatus` (drives the failure text and the retry tooltip)
**W** 16163 `Df` runs when `enableSendPipelineEnhancedErrorHandling` (live true).
The error body is parsed as `{"message":"<json string>"}`, and the inner JSON
gives `errorCode/errorSubCode/subCode`:

| condition | `sendPipelineStatus` |
|---|---|
| transport code `OnlyStoreToCDL` (waiting behind another queued action) | `DEPENDENT_OAM_ACTION` (needs `enableSendPipelineEnhancedRetryTooltips`, live true) |
| transport code `RejectHttpError` (no response) | `REJECT_HTTP_ERROR` (same flag) |
| 400 + `subCode: MessageSizeExceeded` | `MessageTooLong` |
| 400 + `InvalidQuotedMessage` | `QUOTED_MESSAGE_VALIDATION_FAILED` |
| 400 + `TenantExceedMessageLimit` / `MoeraOnlyTenantExceedMessageLimit` | `TENANT_…` / `MOERA_TENANT_MESSAGE_SEND_LIMIT_EXCEEDED` |
| 400 + `ThreadedChatNotEligibleForConversion` | `THREADED_CHAT_NOT_ELIGIBLE_FOR_CONVERSION` (forced terminal) |
| 429 | `SERVICE_THROTTLED` |
| 5xx in the retryable set | `SERVICE_ISSUE_GENERIC` |
| 455 (`enableThreadReadOnlyBanner`) | `THREAD_READ_ONLY` (also sets the conversation `isThreadReadOnly`) |
| 403 (`enableTflPerSubcodeFailureMessaging`) | `QUARANTINE_URLS_BLOCKED` if the content has a URL or the body says `QuarantineURLsBlocked`, else `SPAM_MESSAGE_DETECTED` |
| 404 (same flag) | `CONVERSATION_DELETED` |
| otherwise | null |

### Which failure text appears (533020 `v`, 947361 `mx`/`Fe`)
For a message that never got a server id (96509 `aH`: `!id || id == clientMessageId || id == "-1"`),
the **send** variant is used. Otherwise the **edit** variant is used. Scheduled
messages use the **schedule** variant.

| `sendPipelineStatus` | send text | edit text |
|---|---|---|
| null / other | **Failed to send.** | Failed to edit. |
| `MessageTooLong` | **Failed to send. Message too large.** | Failed to edit. Message too large. |
| `CONVERSATION_DELETED` | **Message didn't send. Check your connection or try again later.** + "Report a problem" link | same |
| `TENANT_…LIMIT_EXCEEDED` | Message limit reached | same |
| `SPAM_MESSAGE_DETECTED` | This message might not meet <link>{{teamsStandardsLinkContent}}</link>. Edit it, and try again. | same |
| `QUARANTINE_URLS_BLOCKED` | You can't send links in this message until the invite is accepted. | same |
| `THREADED_CHAT_NOT_ELIGIBLE_FOR_CONVERSION` | This chat doesn't support threading yet. | same |

So "Message too large." needs a **400 with subCode `MessageSizeExceeded`**. An
HTTP 413 is terminal but shows the plain "Failed to send.". "Check your
connection" is used **only for a 404 (`CONVERSATION_DELETED`)**, not for network
loss: network loss stays in **Retrying**. The composer blocks oversize content
before sending: "Message is too large to send." when the UTF-8 HTML exceeds
`maxMessageContentSize` (live 90112). Interop/SMS messages use other texts,
chosen from `interopDeliveryState`; they are out of scope here.

---

## 3. Offline queue and auto-send (`enableAutoSendV2`, live true)

**With auto-send on**, the composer uses mutation `autoSendMessage … @offlineAction @cache`
(114068 `ht` → 568191). It passes `offlineActionOptions` (114068 `S`):

| field | value |
|---|---|
| `queueId` | `queue_{convId}`. With `enableSendDeleteReplyChainOamQueueing` (live true) and a reply (replyChainId ≠ message id): `queue_{convId}_{replyChainId}`. Optional `_bypassed_{id}` suffix when `enableSendPipelineBypassStuckAction` (unset) |
| `actionId` | `send_{clientMessageId}` |
| `actionType` | `send` (`edit` for Update) |
| `pendingUploadIds` | async uploads still in progress |

The worker middleware (**W** 99317) persists every `sendMessage` call to IndexedDB
**before** running it. `offlineSupportedResolvers` = `sendMessage`,
`setConsumptionHorizon`, `undeleteMessage`, `deleteMessage`.

| metadata | value |
|---|---|
| `maxCrossSessionRetries` | `offlineActionsManagerDefaultCrossSessionRetries` = **10** |
| `expirationDate` | creation + `offlineActionsManagerDefaultActionExpirationInMs` = **172 800 000 ms (48 h)** |
| `numberOfCrossSessionFailures` | starts 0; +1 on every failed execution (in-session or replay) |

Execution:
- The action runs **immediately** if it is the head of its queue. Messages in
  one conversation queue are therefore sent in order, and conversations are
  independent.
- An action that is not at the head is stored, and its lie is written locally
  (`onlyStoreToCDL`).
  - The resolver throws `OnlyStoreToCDL` (→ `DEPENDENT_OAM_ACTION`) before the
    POST only when `enableImprovedActionOrderingAndReplayV2` is on. It is live
    **false**.
  - With live flags, whether such an action still POSTs at once is
    **unconfirmed**.
- On success the action is deleted, and the next action in the queue starts at
  once.
- On a terminal error the action is deleted (`processTaskExecutionStatus(…, isTerminal)`).
- On a retryable error the action stays queued and the client gets a placeholder
  `{id:"oamPollutingId", offlineActionsManagerQueueMetadata:{isQueued:true}}`
  (with `enableExpandedSendPipelineTelemetry`, live true). The UI does not treat
  this as a failure.

**Replay triggers** (**W** 6814 `OfflineActionsSyncStrategy`):
- app start (`onStartup`);
- network offline → online (`onNetworkStateTransition`);
- Trouter `ProviderConnected` after any other state;
- every `offlineActionsSyncStrategyRefreshIntervalInMs` (**600 000 ms**) while
  online. A queue flagged throttled is skipped once.
- Queues are started with a jittered stagger between them: next delay =
  `min(2000, floor(rand × (prev×2 − 100 + 1) + 100))` ms.

**Replay limits** (**W** `OfflineActionsManager.addTask`):

| condition | effect |
|---|---|
| `numberOfCrossSessionFailures == 10` | this run is `isFinalRetry` → a failure now sets **Error** ("Failed to send.") |
| `numberOfCrossSessionFailures > 10` | action deleted without running |
| expired (48 h) | runs once more with `isExpired`, then `maxCrossSessionRetries = -1`, so the next replay deletes it. The send resolver does not check `isExpired`, so an expired message whose last run fails retryably stays **Retrying** (code reading; not observed) |

So a message that keeps failing retryably gets 1 initial run plus 10 replays, and
the 11th failure turns it red. Each run also includes the 5-attempt transport
retries.
- **Dedupe on replay**: when `retryCount > 0`, the resolver first looks the
  message up by `{mri}_{clientMessageId}` (**W** 68245 `Ko`). If it is already
  `Delivered`, it returns that and does not POST again.

**With auto-send off**: there is no OAM. The plain `sendMessage` mutation runs
with the 3 × 30 s client retry (§2a), and any failure goes straight to Error.
The "Sending..." / "Retrying..." text line is shown (§6).

---

## 4. Optimistic message (client lie) and reconciliation

**clientmessageid** (847725 `H1` → 770328 `sN`):
- Two `crypto.getRandomValues` uint32s, written in decimal, concatenated and cut
  to the first **19 characters**. Example: `"3871164259" + "1048093121"` →
  `"3871164259104809312"`.
- Up to 3 tries to avoid a collision with an own message already in the list.
- A failed or edited message reuses its existing `clientMessageId`.

**Lie fields** (**W** 68245 `vt`, then the workflow):

| field | value |
|---|---|
| `id` | `"-1"` (`ClientLieId`). The GraphQL layer maps id `-1` to the clientMessageId, so the UI's id **is the clientMessageId until the server id arrives** |
| `type` | `"Message"` |
| `conversationid` / `conversationLink` | conv id / `"blah/" + convId` (`+ ";messageid=" + replyChainId` for replies) |
| `from`, `fromUserId` | own MRI |
| `composetime` | now, ISO |
| `originalarrivaltime` | now, ISO, then raised to **`max(now, conversation.nonFilteredLastMessageTimeUtc + 1)`**, so the lie always sorts last. The conversation's last-message time is set to that value |
| `content`, `messagetype` | from compose (`RichText/Html` normally) |
| `contenttype` | `"Text"` |
| `imdisplayname` | own display name (`getMeProfile`) |
| `clientmessageid` | as above |
| `callId` | `""` |
| `state` | `0` (Sending) |
| `version` | `"0"` |
| `amsreferences` | AMS image ids, or `[]` |
| `properties` | see §7 |

Placement:
- The timeline sorts by `originalArrivalTime`, so the lie goes at the bottom.
- The worker stores lies in the conversation's client-lie reply chain
  (replyChainId `-1`), keyed by `dedupeKey = "{creatorMri}_{clientMessageId}"`.
  The UI receives the lie through the normal reply-chain subscription.
- A client-side Apollo insert happens only for a not-yet-created chat
  (656562 `Ge`, guarded by `isLie(convId)`).

**Reconciliation**:
- On POST success the workflow sets:
  - `id` = last path segment of the response `Location` header;
  - `version` = that id;
  - `originalarrivaltime` = body `OriginalArrivalTime`;
  - `correlationVector` from the `contextid` header;
  - `state` = Delivered.
- It then re-posts the lie as `ResolveNewClientLie` (`clientLieResolvedTime` set).
- The server echo (Trouter / sync) carries the same `clientmessageid` and
  creator, so it lands on the same `dedupeKey` entry. There is no duplicate.
- **Clock skew**: if the server OAT is earlier than the lie OAT, the
  conversation's `lastMessageTimeUtc`, last message and consumption horizon are
  rewritten to the server time
  (`MessageSendWorkflow:AdjustConsumptionHorizonForClockSkew`).

---

## 5. Failed-message actions

Shown only when the message is failed (`Error`/`Undeliverable`, or
diagnostic/interop failure), **and** it is a lie (never got a server id), **and**
there is no AMS policy error (318259 `getFailedActionMenuProps`,
`shouldHide = !isLie && …`). A failed **edit** of a delivered message shows the
"Failed to edit." text with no buttons.

| action | when | what it does |
|---|---|---|
| **Retry** (`message-failed-retry`, "Retry") | `canRetry` = not a gateway/SMS failure, `sendPipelineStatus` not `TENANT_…LIMIT`, `MOERA_…`, `THREAD_READ_ONLY`, `FILE_UPLOAD_FAILED`, `THREADED_CHAT_NOT_ELIGIBLE…`; chat not disabled; not a delivered scheduled message | 318259 `Ug`: re-sends with `ComponentsMessageSendMessageMutation` (`action:"Create"`), with the **same `clientMessageId`**, the lie `id`, the same content, files and importance, and the old `originalArrivalTime`. The worker finds the stored lie (`{mri}_{clientMessageId}`), copies its id, OAT, composetime and display name (`dn`), and runs the normal workflow (`isRetryFailedMessage`). The OAT is raised again to last+1. This mutation has **no `@offlineAction`**, so a retry is not queued in the OAM. A retryable failure here leaves it Retrying with no replay entry (code reading). A scheduled message more than 3 s in the future re-schedules instead (`kg`) |
| **Edit** (`edit-restricted-message-button`, "Edit") | **only** when `hasRestrictedImage && enableCAPolicyCheck` (pasted image blocked by policy), and not scheduled | opens the normal in-place edit (`onEdit`). **Not shown for ordinary send failures.** The ··· menu Edit is also unavailable, because it needs status Delivered or `enableOfflineEdit` (live false) |
| **Delete** (`message-failed-delete`, "Delete", aria "Delete this message") | always for a failed lie | `deleteFailedMessage(convId, messageId, correlationId, replyChainId)`, with an optimistic removal from the Apollo cache. The worker removes the lie from the client-lie reply chain (`handleDeleteClientLies`). **Local only, no network call.** Whether it also drops a still-queued OAM action is unconfirmed |

**Persistence**:
- Lies are written to the worker's reply-chain IndexedDB store, including
  `lieType` `Send`/`SendError` and the `state`. OAM actions are also in
  IndexedDB.
- So a failed (Error) message survives a restart with its Retry/Delete row. A
  Retrying message is replayed at startup.
- This comes from the code (log text "writing client lie to RCM IDB"). It was
  not verified on the live client.
- Error messages are **never** re-sent automatically.

---

## 6. What the UI shows per state

Layout of an own message (299320):
- name line: `statusMessage` (failed text or Sending title) | timestamp | details;
- content line: `[timestamp-on-hover] [actions] [decorationIcon] [bubble + reactions] [statusIcon]`.

So the failed text sits **above** the bubble, and the Retry/Delete buttons sit
**to the left of the bubble on the same row**. When `statusMessage` is shown,
the name-line details (Edited, etc.) are hidden.

| state | status icon (318259 `bc`, tooltip below the icon) | text line | bubble |
|---|---|---|---|
| Sending, auto-send **on** (live) | Circle, tooltip "Sending..." | **none** (`_shouldShowSending` requires `!isAutoSendEnabled`) | normal |
| Retrying, auto-send on | Circle, tooltip from 533020 `u`: "Retrying..." / "Retrying... Message delayed due to connection issues. Please check your network." (`REJECT_HTTP_ERROR`) / "Waiting for another message action to complete. We'll send this soon." (`DEPENDENT_OAM_ACTION`) / "Retrying... You've reached the current limit. Please wait a moment." (`SERVICE_THROTTLED`) / "The service is temporarily unavailable. We'll retry when it's back." (`SERVICE_ISSUE_GENERIC`) | none | normal |
| Sending / Retrying, auto-send off | same icon | "Sending..." / "Retrying..." (`data-tid="message-sending-title"`, size small) above the bubble | normal |
| Error / Undeliverable | WarningFilled, red (`statusRed`), tooltip "Failed" | failure text (§2c), `data-tid="message-send-failed-title"`, error colour, inside `message-error-container` (`id="message-error-{id}"`, used as the bubble's `aria-labelledby`) | `showFailedBubble` (red, see `messages-and-composer.md` §6) |

Failed action buttons (317519, 862660):
- **Comfy density**: icon-only, `appearance="transparent"`, with a tooltip
  (`title`).
  - Retry: **ArrowClockwise** (Regular/Filled bundle), 16 px (`medium`).
  - Delete: **Delete** icon, `error` styling.
- **Compact density**: buttons with text labels ("Retry", "Delete"), default
  appearance, wrapping, `gap.smaller`, `hAlign:end`.
- **Restricted-image banner** (318259 `Bd`): WarningFilled 18 px, the error
  text, a transparent **Edit** icon button (20 px) and a Delete icon.

Timings:
- No delay before "Sending..." was found in the code; it shows as soon as the
  status is pending (auto-send off only).
- The Retrying tooltip only fires a telemetry event when it opens.
- There is no toast for a failed send.

---

## 7. The POST

```
POST {chatService}/v1/users/ME/conversations/{encodeURIComponent(convId[;messageid=replyChainId])}/messages
content-type: application/json
x-ms-request-priority: 0          (RealTimeSync; the send job runs at REALTIME)
[RegistrationToken: …]           (only with enableMessagingGoldenGateCSV1)
```
(**W** 34565 `We`, 66704, 18823 `gm`, 97722 `Az`). Authentication uses the chat
service's normal `authOptions` (skype token), and `correlationId` is passed to
the HTTP layer. Which other shared headers (`ms-cv`, `x-ms-client-*`) are added
to this request is **unconfirmed**. Targeted messages POST to `…/targetedmessages`.

Body = `JSON.stringify` of the whole lie (§4), **including `"id":"-1"` and
`"state":0`**. `id` is stripped only when the GoldenGate SFL headers are present.
`properties` (**W** 68245 `ns`):

| key | value |
|---|---|
| `importance` | `""` (Standard) / `"high"` / `"urgent"` (**W** 32929) |
| `subject`, `title` | from compose (undefined → omitted) |
| `cards` | JSON string, `"[]"` when none |
| `links` | JSON string (URL preview + embedded links) |
| `mentions` | JSON string `[{"@type":"http://schema.skype.com/Mention","itemid":…,"mri":…,"mentionType":…,"displayName":…}]` or `"[]"` |
| `onbehalfof` | serialized or null |
| `files` | JSON string `"[]"` when none |
| `qtdMsgs` | JSON string of quoted replies |
| `policyViolation` | from compose |
| `formatVariant` | `"TEAMS"` |
| `blurHash`, `meeting`, `crossPostId`, `isSharedInMain`/`sharedInfo`, `isNewSession`, `skipfanouttobots` (bot message-back), `inMeetingPrivateChatContext` | only when relevant |
| `edittime` | only for edits (`PUT …/messages/{id}`) |

Top-level extras when relevant:
- `replyChainId`, `postType`, `crossPostChannels`, `forwardedMessageContext`;
- `fromSipUri`/`toSipUri` (SfB interop);
- `draftDetails` + `threadtype: "streamofdrafts"` for scheduled sends, which go
  to the draft stream instead.

Response:
- 2xx (the exact code is not checked by this code path) with header `Location: …/messages/{serverId}`;
- `contextid` header;
- body `{"OriginalArrivalTime": <epoch ms>}`.

The id is taken from `Location` (**W** 66704
`transformPostMessageToConversationResponse`). A response without an id is
treated as an error (`InvalidResponse`).

`amsreferences` is the list of AMS object ids for inline images. Importance is a
property, not a top-level field.

---

## → Unconfirmed / TODO
- Whether a queued action that is not at the head of its queue still POSTs at
  once with live flags (`enableImprovedActionOrderingAndReplayV2` false).
- Whether a UI Retry that fails retryably is ever replayed (it is not in the
  OAM), and whether Delete of a failed lie removes its OAM action.
- Live `chatService` retry values (only prod defaults read).
  `offlineActionsSyncStrategyRefreshIntervalInMs` and the OAM defaults are also
  prod defaults, because the live `core` dump omits them.
- The extra shared HTTP headers on the POST.
- Restart persistence of failed lies, and the Retrying→Error path after 10
  replays: verify on winpc by sending with the network disabled.
- Exact Griffel values for `actions`/`statusMessage` spacing (hashes not in the
  downloaded chunks).
