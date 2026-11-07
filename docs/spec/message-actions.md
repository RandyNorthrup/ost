# Message ··· menu actions — what each item does (spec)

Source and method are the same as in `messages-and-composer.md`: the published client bundles and
the data-layer worker (`precompiled-web-worker-inner_*.worker.js`), en-us strings resolved
from the obfuscated keys. "Live" means the tenant settings snapshot taken from winpc
(`research/messages/settings-live*.json`). "Default" means the value in the client's own settings
table when the tenant sends nothing.

This file extends `messages-and-composer.md` §13, which has the menu registry, item ids,
labels, visibility conditions and menu layout. Those are not repeated here. This file covers
what happens **after a click**: the service calls, dialogs, toasts and follow-up UI.

Bases used below:
- `{chatsvc}` is the chat service. `{chatsvc}/v1/users/ME/conversations` = `…/conversations`, and `{chatsvc}/v1/threads` = `…/threads`. The request builders are in worker `inner_services_i` module 34565.
- `{csa}` is the chat service aggregator, `https://teams.microsoft.com/api/csa` (region-resolved) + `api/v1/`.
- `{mt}` is the middle tier (`regionGtm("middleTier")`).

All UI clicks go through Apollo GraphQL mutations on the main thread. Each mutation's worker
resolver (inner_d, or `r_data-resolvers-*` chunks) builds the REST call.

---

## Components (module index)
| area | module(s) |
|---|---|
| Copy link (chat) | hook 495364 `kr` (called from 318259 `yu`), base URL 669736, bot-session parent id 669431, preview text 223490, anchor HTML 223398, clipboard 514829 `HT`, text helpers 17033 |
| Copy link (channel) | 81601 `wn`/`Vn`/`zn` |
| Copy link menu item | 629737 `Fa`/`Na`, titles `fa` |
| Forward item | 973348; click handler 282978 (`L`, `saveForwardCard`) |
| Forward dialog | 300780 `er` (dialog), `AB` (picker), `OB` (header), `jB`/`HB` (send/fail); compose buttons 332416 `jn`/`Qn` |
| Forward send | 114068 `$n`/`En` (recipient resolution, toast); worker send workflow `EI.postForwardMessageToConversation` → job → `postForwardMessage` (34565 `fe`) |
| Save | item 66146, hook 603522, worker inner_d 32660 `ve` (RCM), saved slice manager (inner_b `SavedSliceManager`) |
| Pin | item 987814; handlers 318259 `iu`/`ul`/`qg`/`nu`/`su`; unpin 116340; worker inner_d `tg`/`qa`/`Za` |
| Pinned banner / info pane | 866494 (`Zi` → `Ga`, `Co`, `To`, `bo`); 300780 `MO`/`Bm`/`BO` (info pane "Pinned") |
| Read receipt | 629737 `Oo`/`Po`/`Mo`/`vo`/`Ao`; seen calculation 298781 `F` |
| Mark as unread | item 82098, hook 306098; worker inner_d `Pi` (L1), 47447 (V2 path), 25459, 57858 |
| Share to Outlook | 629737 `_n`/`Xn`/`un`/`ss`; task module launcher 82713 `K`; mailbox check 977566 |
| Translate | item 629737 `Cs`/`jn`/`Zn`; submenu 629737 `He` → 339225; mutation 254237; never-translate 204137; auto 59930; settings 187552; status in message 436560; worker inner_b `TranslationJob` (83362), CSA builder 93014 |
| Report | item 629737 `$`/`se`/`M`; dialog 300780 `jk`/`Ik`/`Yk`/`Ck`/`Nk`; submit 816481 `z`; resolvers `r_data-resolvers-chat` `Qt`/`Xt`; unified report service `services-unified-report` 156574 |
| Immersive Reader | 629737 `io`/`ro`/`lo`/`co`/`mo`; token resolver `r_data-resolvers-immersive-reader`; service 977752 |
| More actions | 629737 `Wt` (menu), `kt`/`jt`/`Nt` (L2 contents), `bt`/`xt` (app actions) |

---

## 1. Copy link

### Click
1. Runs `onCopyLink` (chat: 495364 `kr`; channel: 81601 `wn`).
2. Records telemetry and announces **"Copied to clipboard"** (`tmp_messages_copied_to_clipboard`) through aria-live.
3. Calls `actionMenuConfirmationConfig.showConfirmation()` when the copy succeeds. This is the menu's own confirmation; its visual form is unconfirmed.

There is no toast and no keyboard shortcut. Writing to the clipboard is retried up to 3 times. If all
3 fail, the client throws "Failed to copy link".

### Link base (669736)
- If the current origin (`protocol//host`) is listed in `deepLinkDomains`, that origin is used. A `local.` prefix is stripped and `teams.office.com` is replaced with `teams.microsoft.com`.
- Otherwise the first entry of `deepLinkDomains` is used. If that setting is missing, `https://teams.microsoft.com`.
- Live `deepLinkDomains` = `["https://teams.microsoft.com", "https://teams.cloud.microsoft"]`. A native client should use `https://teams.microsoft.com`.

### Chat message link (495364 `v`)
```
{base}/l/message/{convId}/{messageId}?context={ctx}
{base}/l/message/{convId}/{messageId}?parentMessageId={parent}&context={ctx}
```
- `ctx` = `encodeURIComponent('{"contextType":"chat"}')`, which is `%7B%22contextType%22%3A%22chat%22%7D`.
  - For the notes-to-self chat `48:notes`, `ctx` = `{"contextType":"chat","oid":"<currentUserId>"}`.
- `parentMessageId` is added only when there is one. It is taken, in order, from:
  1. the reply-chain id, when it differs from the message id (thread reply in a threaded chat);
  2. otherwise `originalParentMessageId`;
  3. otherwise, in a 1:1 bot chat with bot sessions on, the message's own id (`enableSessionsInOneOnOneBotChat`, live false).
- There is no `tenantId`, `groupId` or `createdTime` in chat links.

### Channel post / reply link (81601 `zn`)
```
{base}/l/message/{channelId}/{messageId}?tenantId={tid}&groupId={hostTeamGroupId}
  &parentMessageId={parentId || messageId}&teamName={enc(teamDisplayName)}
  &channelName={enc(channelDisplayName)}&createdTime={originalArrivalTime ms}
  [&ngc=true][&allowXTenantAccess=true][&owningTeamId={enc(owningTeamId)}]
```

| param | value |
|---|---|
| `messageId` | `sharedFromMessageId` if the message was shared from a thread, else the message id |
| `tenantId` | Shared channel: `hostTenantId` or else the user's tenant. Other channels: the user's tenant or else `hostTenantId` |
| `parentMessageId` | `sharedFromReplyChainId`, else the root post id (for a reply), else the message's own id (a post links to itself) |
| `createdTime` | `new Date(originalArrivalTime).getTime()`, or `0` if missing |
| `ngc=true` | channel type Private, Shared or Standalone, when `addChannelMessageDeepLinkNgcQsp` (live true) |
| `allowXTenantAccess=true` | Shared channel, when `addChannelMessageDeepLinkAllowXTenantAccessQsp` (live true). With `enableConditionalAllowXTenantAccessParamForNGCDeeplink` (live absent) it is added only for Teams Connect channels |
| `owningTeamId` | only with `addOwningTeamIdInCopyLink` (live absent) |

A link that does not start with `http(s)` is refused ("Failed to copy channel link: invalid HTTP(S) URL").

### What goes on the clipboard (514829 `HT` → `D`)
Two formats are written in one `copy` event. The fallback is `navigator.clipboard.write([ClipboardItem])` with the same two blobs.
- `text/plain` = the bare link URL.
- `text/html` = `<div itemprop="teams-copy-link"><a href="{url}"[ title="{url}"]>{text}</a></div>` (223398). `&`, `<`, `>`, `"` and `'` are HTML-escaped in both url and text. The `title` attribute is set **only for channel links**.

The anchor text:

| | text |
|---|---|
| chat | `truncate("{{displayName}}: {{messageContent}}", 85 − len(suffix)) + suffix`. `displayName` = `imDisplayName`. Truncation uses lodash `truncate`, so it ends in `...` |
| chat, `enableStandardizedLinkPreview` (live **false**) | `{text} \| {chatTitle or shortTitle or "Chat"} \| Microsoft Teams`. A 1:1 chat uses `chatTitle`, else "Chat" |
| channel | `truncate("{{displayName}}: {{postSubject}}", 85)` + ` \| {channelName}` (if a channel name exists) |
| channel, standardized | `{text} \| {teamName} > {channelName} \| Microsoft Teams` (`<` in RTL). For the General channel with `excludeChannelNameFromLinks` (live false): `{text} \| {teamName} \| Microsoft Teams` |
| forwarded message with no own text (standardized only) | "Forwarded message" |

- If the sender name is missing in a channel, it is fetched with `user(userId){displayName}`.
- `messageContent` / `postSubject` (223490 `L`):
  - The sanitized message HTML with tags stripped and whitespace collapsed.
  - `<img>` becomes "📷 Image" and `<video>` becomes "🎥 Video". A trailing "📷 Image"/"🎥 Video" is kept after truncation as `suffix`.
  - A quoted reply becomes "`{author}: {preview}`".
  - Channel posts use the subject first, then an announcement title or meeting title, then the body.
  - Empty bodies fall back to:

| content | text |
|---|---|
| Loop/Fluid card | Sent a Loop component |
| voice message | 🎙 Audio message |
| code snippet card | card name, else "Sent a code snippet" |
| other card | Sent a card |
| image file | 📷 Sent an image |
| GIF (giphy file or `.gif` img) | 📷 GIF |
| inline video file | 🎥 Video |
| other file | Sent a file |
| MediaCard bot message | "{{title}} message" (from `imDisplayName`) |
| deleted | "" |

### Strings
- Item text: always **"Copy link"** (`messages_copyOtherLinkDropdownOption`).
- Item title / aria by `__typename`:
  - `Message` → "Copy message link"
  - `ReplyChainMessage` → "Copy reply link"
  - `StandardPostMessage`/`AnnouncementPostMessage` → "Copy post link"
  - otherwise "Copy link".
- The info pane's pinned-message menu uses "Copy Link" (`tmp_message_copy_link`, capital L). It runs the same chat hook.

---

## 2. Forward

### Menu item (973348)
- With multiselect enabled, it is a split button (see §13 of the composer spec).
- Click → 282978 `L`:
  1. Collects stats (image count, files, Loop count, app cards, app ids to install).
  2. Writes a cached **forward card** for each selected message: client-only mutation `saveForwardCard(convId: <forward-compose sentinel>, messages)`. This is what the dialog shows as the preview.
  3. Calls `entityCommanding.chat.launchForwardMessage({messageIds, convId, messageContents, messageContentSize, forwardAppIdsToInstall, messageOriginalSender, isForwardMultiselect, selectedMessages[{id,from}]})`.
  4. When the dialog closes, focus returns to `[data-mid="{firstSelectedId}"]`.
- Forward-card normalisation (282978 `v`):
  - Already-forwarded content is unwrapped to the original sender and arrival time. A single forward has its inner blockquote extracted.
  - Markdown/code content is converted.
  - MediaCard attachments become cards.
  - Fluid embed `itemid` is rewritten to the card's `cardClientId`.
- Shortcut **F** (`ForwardMessage`, `enableForwardMessageKeyboardShortcut` live true).

### Dialog (300780 `er`; `data-tid="forward-message-dialog"`)
Fluent Dialog, top to bottom:

| part | content |
|---|---|
| header (`OB`) | Title **"Forward this message"** (`forward_message_dialog_header`). Subtitle **"You can forward to any chat or channel."** (`forward_message_dialog_sub_header`, class `forwardDialogSubheader`). The X close button is only in the file/recap variants |
| label | **"Add recipients"** (`forward_dialog_people_picker_label`), required |
| people picker | Placeholder **"Enter name, email, group or tag"** (`chats_addRecipients_inputPlaceholder_allow_groups_and_tags`). Autofocus. Clears its query after each selection. No zero-state suggestions. Hides the signed-in user unless self-chat forwarding is allowed (`enableForwardMessageSelfChatInitiation` live true) |
| validation line under the picker | more than one recipient: ⓘ **"Message will be forwarded to a group chat"**. A federated or external target and the message has files: error **"You can't forward files to people outside your org"** |
| label | **"Message preview"** (`forward_dialog_compose_label`) |
| compose (universal compose, `enableForwardMessageUniversalCompose` live true) | Shows the forward card preview (from `saveForwardCard`) and the optional note editor. Placeholder **"Add a message (optional)"** (`forward_message_compose_placeholder`) |
| footer | **Cancel** (`forward_message_dialog_cancel`) and primary **Forward** (`data-tid="forward-message-button"`) |

- **Recipient search filters** (`Y1`):
  - Initially: people, plus channels with post permission and teams (`enableForwardToChannel` live true).
  - After the first pick: group chats, meetings, unnamed group chats, channels and teams are still offered while `includeGroupChats` is true.
  - Once one group chat or channel is picked, the picker switches to single selection (`forwardMessageSingleSelection`) and its input is disabled.
  - Picking people only keeps group chats out.
- **Forward enabled** when at least one recipient id resolved and there is no file-to-external error. A note is not required. A second click is suppressed (duplicate-submission guard).
- **Esc**: the "Esc closes when no recipients and the draft is empty" handler (`Br`/`K4`) is wired only for file quick-share. For message forward the dialog has no `onOpenChange` handler, so Esc behaviour is unconfirmed. Cancel closes it.
- Limit checked before the dialog opens: more than `maxForwardMessageImageCount` images (live 5) disables the menu item (composer spec §13).

### Send (114068 `$n` → `En`)
1. Resolve the target conversation:
   - one selected chat or channel → its id;
   - one person → `chatWithUser(userId, createLieIfNotFound:true)`;
   - several people → `chatsWithUsers(userIds ∪ me, createLieIfNotFound:true)` (the first existing chat with exactly those members).
   - If the result is a local "lie" chat, `createChat(userIds, …)` creates it first.
2. `sendMessageWorker(action, convId: target, message: preparedMessage)`. The prepared message is the compose note (possibly empty) carrying `forwardMessageIds`, `forwardMessageOriginalConvId` and `forwardAppIdsToInstall`.
3. Worker send workflow:
   - When both forward fields are present, the message's `properties.cards` is moved to `properties.originalMessageContext = {cards}`.
   - It then calls

```
POST {chatsvc}/v1/users/ME/conversations/{originalConvId}/messages/forward
content-type: application/json   (+ SFL headers when GoldenGate is on)
{
  "targetThreadIds": ["{targetConvId}"],
  "messageIds": ["{id}", …],
  "additionalMessage": { …normal chat-service message object: content = note HTML,
                         messagetype, contenttype, clientmessageid, imdisplayname, properties … },
  "templateId": "basic_forward_message_template"
}
```
   The URL holds the **source** conversation. The target goes in the body. (The composer spec §13/§21 says `{target}`, which is wrong.)
   - The response is an array of per-target results. Any entry with a status outside 200–299 or with `error` set fails the job. The new message id (`messageId`) replaces the local id.
   - Apps in `forwardAppIdsToInstall` are JIT-installed first (`enableACv2JITInstallFromCDLv2`).
   - Special case: when either conversation is a comment stream (`T.IF`), a CSA path is used instead.
4. Toasts:
   - Success: **"Message forwarded"** (`forward_message_confirmation_toast`), intent Success, 5000 ms, id `forward-message-success`.
   - With `enableForwardSuccessToastViewButton` (live **false**), the toast also has a **View** action that opens the target chat or channel at the new message.
   - Failure: **"Failed to forward"**, intent Error, 2000 ms.
   - Aria-live: "Message forwarded" / "Message failed to forward".
5. The server builds the delivered message: `<blockquote itemtype="http://schema.skype.com/Forward">…</blockquote>` plus the note, with properties `forwardTemplateId` and `originalMessageContext`. Its rendering is specified in `message-types.md` §16. The worker constants are `ForwardedContentStart` = `<blockquote itemtype="http://schema.skype.com/Forward">` and `ForwardedContentEnd` = `</blockquote>`.

---

## 3. Save / Unsave

- Labels:
  - **"Save this message"** / **"Unsave this message"** (`icons_bookmark` / `icons_bookmarked`).
  - When saved, a description tooltip: "Saved by you. Others won't see that it was saved."
  - Bookmark icon.
  - Shortcut **S** (`enableSaveMessageShortcut` live true).
  - Disabled offline, and when saved with `disableUnsaveMessageAction` (live false).
- Click:
  1. Announces "Message saved" / "Message unsaved".
  2. Runs mutation `setReplyChainSaveState(conversationId, replyChainId, messageId, save)`.
     - With `enableSaveSharedFromL2` (live true), a message shared from a thread uses its `sharedFromMessageId` / `sharedFromReplyChainId`.
     - The optimistic response writes `userHasSaved` on the message right away, so the label toggles at once.
- Worker (inner_d 32660 `ve`):
```
PUT {chatsvc}/v1/users/ME/conversations/{convId}/rcmetadata/{replyChainId || messageId}
content-type: application/json
{"s": 1 | 0, "mid": <parseInt(messageId)>}
```
  - Retry (`savedOperationRetry`, default `{retryWindow:30000, maxRetries:3, backoffTime:10000}`) on retryable HTTP statuses.
  - If the backend fails, a local RCM lie stays in place and the mutation rejects.
- **Read back**: reply-chain metadata (RCM) comes from `GET …/{conv}/rcmetadata?startTime=&pageSize=` and `POST …/{conv}/getrcmetadata {rootMessageIds:[…]}`.
  - RCM fields: `s` (root saved, `=== 1`), `sl2` (saved reply ids), `f` (follow), `r`/`rl2` (reminders), `ch`/`chb`/`chbv` (L2 consumption horizon / bookmark), `lu`.
  - The worker maps them to `isRootSaved` and `savedL2Ids`, which drive the message's `userHasSaved`.
  - The exact mapping for replies (`mid` ≠ rcId → `sl2`) is inferred from the field names (unconfirmed).
- **Toasts** (`enableSavedToast`, default true):
  - Save success: **"Your item has been saved"**, intent Success, with action **View**. View opens the Saved slice (`slices.saved`, or `slices.savedChat`/`slices.savedChannel` in split view) in the main window.
  - Unsave success: no toast.
  - Failure: "Your item couldn't be saved" / "Your item couldn't be unsaved", description "Try again later", intent Error.
- **Saved view**: the saved slice manager reads the private feed stream **`48:saved`** (`SavedConversationId`). It syncs like a conversation, and each item carries `sourceMessageId`/`sourceThreadId`.
  - Filters: All / Chats only / Channels only.
  - Empty-state keys: `simple_collab_empty_saved_slice_message_chat` / `…_channel`.
  - A legacy path (`saveMessage`/`unsaveMessage`: a `star` emotion plus a copy into the saved stream) still exists in the worker but is not used by the menu.

---

## 4. Pin / Unpin ("Pin for everyone")

- Labels:
  - **"Pin for everyone" / "Unpin for everyone"**. Both string pairs (`message_action_pin_button_label` and `…_for_everyone_…`) resolve to the same text, so `enablePinUnpinPostForEveryoneText` (live false) makes no difference.
  - Icons Pin / PinOff.
  - Shortcut **P** (`enablePinMessageShortcut` live true).
  - Disabled offline.
- **State** (318259 `ul`): `chat(convId){pinnedConversationItems{id}}` from the cache.
  - With `enableMultiplePinnedMessages` (default **true**), the message is pinned if its id is anywhere in the list.
  - Otherwise only if it is item 0.

### Click (318259 `iu`)
| state | action |
|---|---|
| pinned | unpin (see below), announce "Message unpinned" |
| not pinned, another pinned, multiple **off** | **Replace dialog** (`launchReplaceMessageFromChat`): "Replace the current pinned message?". Confirming pins |
| not pinned, multiple on, count ≥ `maxNumberOfMultiplePinnedMessages` (default **10**) | **Max dialog** (`launchMaxPinnedMesssagesReachedDialog`): title "Replace a pinned message", body "Max of {{maxNumberOfMultiplePinnedMessages}} pinned messages has been reached. Unpin a message to pin a new one." (or the default text without the number), button "Close". Nothing is pinned |
| otherwise | pin, announce "Message pinned" |

### Legacy storage (live path: `enableTabsPlusPlus` live false, so not the pinbar)
- Mutation `setPinnedItemsThreadProperty(convId, pinnedConversationItemInfo:{itemId, itemType:"Message"}, isUnpin)`.
- Worker `tg`:
  1. Reads `threadProperties.pinnedItems` (a JSON string, `[]` if missing or invalid).
  2. Pin (`qa`): `unshift({itemId, itemType:"Message"})`, so the newest is first.
     - With multiple off, an existing entry moves to the front. If the list is at max, the last entry is dropped first.
     - With multiple on, the worker does not enforce the limit; the client dialog does.
  3. Unpin (`Za`): removes the entry.
  4. Writes:
```
PUT {chatsvc}/v1/threads/{convId}/properties?name=pinnedItems
content-type: application/json
{"pinnedItems": "[{\"itemId\":\"1730000000000\",\"itemType\":\"Message\"}, …]"}
```
- Deleting a pinned message unpins it automatically (delete resolver `Ia`/`Bn`).
- Toasts "Message pinned" / "Couldn't pin message" / "Message unpinned" / "Couldn't unpin message" appear **only on the pinbar path** (`enableTabsPlusPlus && enablePinnedTabsCsaApi`). On the live legacy path there is only the aria announcement.
- The server posts control messages "**{name}** pinned a message." / "… unpinned a message." (`message_pin_control_message_tmp` / `message_unpin_control_message_tmp`).
- After pinning with multiple on, when the info pane is closed and this is not a side chat, the client calls the info-pane state hook with `"closed"`. The visible effect is unconfirmed.

### Pinbar path (not live)
- `chatPinUnpinPinbarMessage(isPinned, chatId, messageId, pinbarId: chatId, pinbarItemId | pinbarPinnedMessageId)`, through the middle-tier pinned-tabs API.
- In this mutation `isPinned:false` means "pin" and `true` means "unpin". That is the current-state convention.

### Pinned-message banner (866494 `Zi` → `Ga`; above the message list)
- **Shown when** `enablePinMessageToChat` (live true) and the chat has a pinned message. It is hidden on the pinbar path.
- Data:
  - `chat.pinnedMessages.edges`, kept up to date by subscription `chatPinnedMessageEvents(threadId){pinnedItems, events{ChatPinnedMessageAddedEvent{edge{node{id,content,from,fromUserId,imDisplayName,messageType,originalArrivalTime,deleteTime,files,cards}}}, ChatPinnedMessageRemovedEvent{id}}}`.
  - **Only edge 0 (the newest pin) is shown.**
- Layout: a horizontal Flex with `gap.medium`, vertically centred, `dir` following the locale. Its `data-tid="pinned-message-banner"` is a transparent full-width button. Left to right:
  1. Pin icon, 20px (`fontSize large`).
  2. Sender name, small regular. It is masked for masked meeting attendees, and the fallback is "Unknown User".
  3. Preview, small semibold, single line truncated. It has a Loop icon for `Collaborate`. The fallback while loading is "Loading...".
  4. Timestamp, small (`getFormattedDate`; exact format unconfirmed).
  5. On the far right, a "···" button `data-tid="pinned-more-menu"` (aria "Pinned options"), menu below-end:
     - **View in chat** (Open icon): scrolls to and focuses the message.
     - **Unpin for everyone** (PinOff icon): only when the user may unpin (chat sub-type and membership). Runs 116340, then focus moves to the message pane.
     - divider + **See all**: only with multiple pins and not in a side chat. Opens the info pane at `chatpinnedmessagesdetails` and saves that as a client preference.
- A click on the banner body scrolls to the message (`ChatScrollToPinMessage`).
- Aria label: "Pinned message banner. Message from {{userDisplayName}} sent on {{arrivalTime}}, {{message}}".
- **Info pane "Pinned"** (300780):
  - Section title "Pinned". The details view has a Back button ("Back") and Esc goes back.
  - Each row: avatar with presence, header = preview, secondary = "{name}, {time}". Its "···" menu has **Unpin for everyone**, **Copy Link**, **View in chat**.
  - A click on a row deep-links to the message.

---

## 5. Read receipt ("Read by N of M")

- Shown for own messages in group chats (condition in composer spec §13), and only once members' consumption horizons have loaded.
- Data (629737 `Ao`):
  - `chat(convId){memberIds, substrateGroupId, tenantId}`.
  - `membersConsumptionHorizon(convId)` (cache-and-network; `GET {chatsvc}/v1/threads/{id}/consumptionhorizons`, composer spec §7).
- **Who has read** (298781 `F`):
  - Members other than me, filtered to current `memberIds`.
  - A member has read when `messageArrival ≤ consumptionhorizon.originalArrivalTime` (the first `;` field) **and** `messageArrival ≥ messageVisibilityTime`.
  - `total` = member count minus me.
  - The list keeps the order of the horizons response.
- Names: batch user lookup (`po.n_`, area `messageReadReceipt`, shared-channel aware). The fallback is "Unknown user".
- Item:
  - **"Read by {{membersCount}} of {{total}}"** (`message_readReceiptsOption`), Eye icon, `data-tid="message-actions-read-receipt"`.
  - "No receipt info available" when `total` is 0.
  - **Disabled** (no submenu chevron) when nobody has read it.
- Submenu: opens to the side (`position:"after"`, `autoSize:"height-always"`) at viewport ≥480px, otherwise below.
  - One plain row per reader, display name only (`id="message-read-receipt-item-name-{mri}"`). No avatar or time.
  - A click opens a 1:1 chat with that person (`chatWithUsers([mri])`, stateTransition `new`).

---

## 6. Mark as unread

- Label **"Mark as unread"**, shortcut **U** (`enableMarkMessageUnreadShortcut` live true).
- Afterwards it announces "Message marked as unread". It then refreshes the thread unread summary (thread pane / threaded views).
- **Live path** (`enableConsumptionHorizonV2Mutations` live **false**, 306098):

| where | mutation | REST |
|---|---|---|
| L1 (chat, or a channel post in the list) | `setConversationConsumptionHorizonBookmark({convId, message:{clientMessageId, originalArrivalTime}})` | `PUT {chatsvc}/v1/users/ME/conversations/{convId}/properties?name=consumptionHorizonBookmark` with body `{"consumptionHorizonBookmark":"{oatMs−1};{nowMs};{clientMessageId}"}` |
| L2 (thread pane, or a reply in a non-L1 view) | `setReplyChainConsumptionHorizonBookmark(conversationId, replyChainId, chBookmarkTimestamp: oatMs)` | `PUT {chatsvc}/v1/users/ME/conversations/{convId}/rcmetadata/{replyChainId}` with body `{"chb": <ms>}` |

  - `oatMs` = the message's `originalArrivalTime`.
  - In the L1 view, when the surrounding reply-chain context provides a `latestMessage` (channel post with replies) and the view is not ConvUX, that latest message is used instead. This makes the whole thread unread.
  - `clientMessageId`: `"0"` if missing. If it contains `_`, the part after the `_` is used.
  - Whether the legacy L2 resolver also subtracts 1 ms is unconfirmed.
- **V2 path** (`markMessageAsUnread`, worker 47447; not live):
  - The same property and RCM writes.
  - The value is `oat−1` for both L1 and L2. A write happens only if the new value is earlier than the current consumption horizon and earlier than the existing bookmark (or the bookmark is 0).
  - The thread and messaging slices are flipped to unread.
- The consumption horizon itself (`consumptionhorizon`) is **not** changed. The "unread" state is the bookmark lying behind the horizon.

---

## 7. Share to Outlook

- Item **"Share to Outlook"** (`share_to_outlook_text`), `data-tid="message-share-to-outlook"`, disabled offline.
- Shown only when the user's Exchange mailbox is discoverable (977566 `S`: `isOnCloud` live true, plus autodiscover with `enableOutlookSharingEWSDeprecation` live true).
- Click opens a **task module** (dialog hosting a web app; 82713 `K` → `entityCommanding.platform.launchTaskModule`):
  - `entryPoint`: ShareToOutlook
  - `appId`: `shareToOutlookConfig.appId`, live `40517485-2262-4135-b174-401da4aa6f0f`
  - `appName`: "Outlook"
  - `title`: "Share conversation over email"
  - `messageId`: `sharedFromMessageId` or else the id
  - `threadId`: convId
  - `bodyType`: `"SingleMessage"` in threaded/ConvUX contexts, else unset
  - `url`:
```
{stoWebAppUrl || "https://teams.microsoft.com/sto"}?threadId={convId}&messageId={id}
  [&desktopVersion={enc}][&owaParams={enc}][&useRedirect={enc}][&loadingTimeoutSeconds={enc}]
```
    Live `shareToOutlookConfig` = `{enabled:true, appId:"40517485-…", loadingTimeoutSeconds:20, owaParams:""}`. An empty `owaParams` is omitted, so the live URL ends in `&loadingTimeoutSeconds=20`.
- The task module is cancelled in the notes-to-self chat.
- On close, focus goes to the first tabbable element of the message.
- What the Outlook web app shows inside the dialog comes from that web app, not from the client (unconfirmed).

---

## 8. Translate and the Translation submenu

### Which entry shows
- **Chats**, when `enableTranslationIntelligentSuggestions` is on, or `enableTranslationOverflowMenuV2` is on and the message is already translated (both live true): the **"Translation" ▸** submenu (`tmp_messages_intelligentTranslation_translationMenu`, Translate icon, `data-tid="message-actions-translation-menu"`, opens on hover) is shown, and the plain item hides.
- **Channels**: plain item. It reads "Translate" (`messages_onDemandTranslate_translate`), or "See original message" once translated.

### Submenu items (339225 `L`, in order)
| item | shown | action |
|---|---|---|
| "Translate" / "See original message ({{originalLanguage}})" (no language: "See original message") | always | toggle (below) |
| "Turn on auto-translation" | chat, `enableAutomaticTranslationV2` (live true), auto-translate off, message not in the preferred language | set `translationMode = "ALWAYS_TRANSLATE"`, then re-open the chat at this message (`bypassCacheForDeeplink`) |
| divider | | |
| "Never translate {{language}}" | chat, intelligent suggestions on, source language known, message not in the preferred language | add the source language to `knownLanguages`, untranslate if translated, re-open the chat at the message |
| "Settings" | always | `settings.launchSection(settingSectionId:"translation-settings")` |
| "Give feedback" | chat, feedback flag | translation feedback popover |

- Translation settings `{targetLanguageCode, translationMode, knownLanguages}` live in worker local storage.
- With `enableTranslationSettingsRoaming` (default true) they are also sent to the middle tier through `startLanguageAccountSettingsUpdateWorkflow`. That endpoint was not traced (unconfirmed).

### Toggle (254237)
- Chat mutation: `updateMessageTranslation(conversationId, messageId, correlationId, translationAction: "Translate"|"Untranslate", translationType:"OnDemand")`.
- Channel mutation: `updateChannelsMessageTranslation(teamId, …, localeCode)`.
- The optimistic status is `InProcess`, or `ShowOriginalMessage` when untranslating.
- Aria announcements:

| status | announcement |
|---|---|
| Done | "Message translated." |
| ShowOriginalMessage | "Message untranslated" |
| InProcess | "Translating" |
| failure | "Translation failed. Retry." |

- Worker `TranslationJob` (inner_b 83362):
  - **Untranslate** only flips the cached `translation.toggled`. No request is made.
  - **Translate** re-shows a cached translation if one exists for the same target language. Otherwise it calls CSA:
```
POST {csa}/api/v1/chats/{convId}/messages/languages/{targetLang}
Content-Type: application/json
x-ms-request-id: {correlationId}
x-ms-use-acs-translation: true
x-ms-on-demand-translation: true            (on-demand; otherwise x-ms-knownLanguages: xx)
[x-ms-sourceLanguage: {code}]
[{"id":"{messageId}"}]                      (+"isTargetedMessage" with enableTargetedMessagingTranslate)
```
  - The channel variant is `POST {csa}/api/v1/teams/{teamId}/channels/{channelId}/{rootMessageId}/messages/languages/{lang}`.
  - Response: an array of `{id, version, resultCode, translatedContent, translatedSubject, translatedTitle, detectedLanguage:{languageId, score}}`.
  - `resultCode` maps to:

| resultCode | status |
|---|---|
| Success | Done |
| MessageNotFound | MessageNotFound |
| VersionNotFound | VersionNotFound |
| LanguageDetectionFailed | LanguageDetectionFailed |
| SkipTranslation / ContentIsEmpty | TranslationNotNeeded |
| anything else | UnknownError |

  - A network failure marks all requested messages `UnknownError`.
  - The supported-languages list comes from `GET {csa}/api/v1/translator/languages?locale={locale}`.
  - The target language is the user setting. It defaults to the UI locale reduced to its language: `zh-*` → `zh-chs`/`zh-cht`, and the `tcurlang` cookie wins.
  - The menu item's `translationConfidenceScoreThreshold` is 0.3.
- (The composer spec §13/§21 calls this a middle-tier call. It goes to CSA.)

### How the translated message looks (436560)
- The bubble body is replaced by `translatedContent`, and the subject by `translatedSubject`.
- Next to the timestamp:

| state | display |
|---|---|
| Done, chat | Translate-outline icon button, tooltip "Translated from {{language}}" (or without a language). Its menu (above-start) has **"See original message"** and, behind a flag, a divider and **"Give feedback"** ("Thank you for your feedback!" afterwards) |
| Done, otherwise | static icon with the same tooltip |
| InProcess | extra-tiny spinner |
| TooManyCharacters | error icon + "This message is too long to translate" |
| ScoreTooLow / UnknownError | error icon + "Failed to translate" |

---

## 9. Report this message (report-a-concern)

- Item:
  - **"Report this message"** (`enableUpdatedCCReporting` or `enableReportingAsSecurityRisk`, both live true). Otherwise "Report a concern".
  - `data-tid="message-report-a-concern"`, disabled offline.
  - It has its own divider and sits at the top level (composer spec §13).
- Click → 318259 `_onReportAConcernV2Click` → a dialog with `{contactMri, convId, messageId, version, content, author, isFromCurrentUser, policyViolationType}`.

### Dialog (300780 `jk`; `modalType:"alert"`, `data-tid="chat-report-a-concern-v2-dialog"`)
- Enabled report types (`kk`):
  - Inappropriate = `allowCommunicationComplianceEndUserReporting`. This is a user policy, absent from the settings snapshot (unconfirmed for this tenant).
  - Security risk = `allowSecurityEndUserReporting` (live true).
  - Not-a-security-concern = `allowReportWrongDetection` (live true).
  - For external users with `enableSecurityEndUserReportingForExternalUsers`, Inappropriate is turned off.
- **Title** (`Nk`):

| case | title |
|---|---|
| several types enabled, someone else's message, inappropriate selectable | "Report this message as inappropriate" (`…UpdatedDialogTitle`) or "Report a concern" |
| security risk only | "Report a security concern" |
| wrong-detection cases | "Report as not a security concern" |

- Header has an X button (aria "Close").
- **Body** (`Ik`), top to bottom:
  1. Subheader, only when inappropriate is the only choice: "Examples of inappropriate include harassment, violence, nudity, and disturbing content."
  2. A static quoted-reply card of the message (author + preview).
  3. A **dropdown** "Select report type", shown when several types apply and it is not your own message. Options:
     - "Inappropriate - Harassment, violence, nudity, and disturbing content" (`reportAsInappropriate`)
     - then either "Security risk - Spam, phishing, malicious content" (`reportAsSecurityRisk`) or "Not a security concern - incorrectly identified as a concern" (`reportNotSecurityConcern`).
  4. A **justification** single-line input, shown unless "inappropriate" is selected. Placeholder "Enter an explanation (optional)", max **250** chars, counter "`{n}/250 maximum characters`". Over the limit: "Maximum 250 characters allowed."
  5. A **footer text** chosen by type:
     - Security risk: "Information about this message will be shared with your IT admin and Microsoft. Microsoft may use the information to improve the accuracy of detection. [Learn more]"
     - Inappropriate: "This message, along with five messages preceding and following it, will be shared with an internal reviewer (the sender will not be notified). The review process is fully determined by your organization."
     - Not a concern: "Information about this message will be shared with Microsoft. Microsoft may use the information to improve the accuracy of detection. [Learn more]"
     - Learn more link `https://learn.microsoft.com` (or `…/microsoftteams/security-report-privacy` with `enableReportMessagePrivacyFooter`).
  6. On error: a warning icon and "Report didn't send. Try again." (also announced).
- **Footer**: **Cancel** and primary **Report**.
  - While sending, the button reads "Reporting" and both buttons are disabled.
  - Report is disabled (aria "Report button disabled") when several types apply and none is selected.
- **Submit** (`Yk`):
  - The report key is `securityRisk` for security risk or not-a-concern (and for own messages or security-only setups); otherwise `reportMessage`.
  - `securityRisk` with `enableUnifiedReportAPI` (live true) → `reportMessageToUnified`:
```
POST {mt}/beta/reports
{"reportTimestamp":"<ISO>","reportType":"message","threadId":"{convId}","messageId":<number>,
 "actions":[],"category":"Security"|"SecurityFalsePositiveMU"|"SecurityFalsePositivePD","comment":"<justification>"}
```
    The category comes from the policy-violation type: `mu` → MU false positive, `pd` → PD false positive.
  - Otherwise → `reportOffensiveMessage(conversationId, messageId, reportKey, reportDetails{timestamp: "<ms>", messageVersion, [category:["mu-fp"|"pd-fp"]], [comments]})`:
```
PUT {chatsvc}/v1/users/ME/conversations/{convId}/messages/{messageId}/properties?name=userReportedData
{"userReportedData":{"key":"reportMessage"|"securityRisk","value":{…reportDetails}}}
```
    (The exact body wrapper is inferred from `setMessageProperty`.)
- On success the dialog closes (`confirmed`). No follow-up toast or thank-you screen was found for this V2 work dialog (unconfirmed). The "Thank you for reporting" dialog (949983) belongs to the consumer (TFL) flow.

---

## 10. Immersive Reader

- Item **"Immersive Reader"** (`messages_immersiveReaderOption`), `data-tid="message-actions-immersive-reader"`, disabled offline.
- Click (`allowImmersiveReaderV2` live true):
  1. GraphQL `immersiveReaderAuthToken`, which is an AAD token for resource `immersiveReaderServiceUrlV2`, live `https://immersivereader.cloud.microsoft`. On failure the token is `"anonymous"`.
  2. Then Immersive Reader SDK `launchAsync(token, {chunks}, {parent: document.body, cognitiveAppId:"Teams", useWebview2:true, onExit})`. The reader is a **full-window iframe web app**: `position:fixed; 100vw×100vh; z-index:1000; background:white`.
- Chunks (`mo`), all `text/html`:
  1. `"{imDisplayName} {toLocaleDateString} {toLocaleTimeString} <br/>"`
  2. `"<br/>{subject}<br/>"` (only when there is a subject)
  3. The message HTML. Adaptive-card and MediaCard content is flattened to text and spliced in place of the card placeholder.
- On exit, focus returns to the message container.

---

## 11. "More actions" submenu

- Label **"More actions"** (`messages_takeAction`), with its own divider (`more-option-divider`). Opens on hover, positioned with `autoSize:"height"`.
- **Disabled** when L2 has nothing to show (`qt`).
- Contents (`kt` → `jt`):
  1. The L2 secondary items that are not "docked", inside a padded wrapper.
  2. Then items with `shouldDockInL2` (e.g. `report-a-concern` when it is not raised to the top level).
  3. An item with `hasDivider` gets a divider before it.
- App actions: message-extension "action" commands of installed apps (`bt`/`xt`, dynamic actions with `enableDynamicActionsWithPerfImprovements`) are merged in with `unionBy(id)`.
  - With usage sorting (`enableAppActionsUsageRendering` live true) the list is ordered by recent use.
  - Each click records usage (`recordActionUsage(actionId, appId)`, id format `{appId}{sep}{actionId}`).
- Whether trailing "Create new action" / "Get more apps" entries exist was not found (unconfirmed).

---

## 12. Keyboard shortcuts (menu items show the text; from 504800 / 714901)
| key | item |
|---|---|
| F | Forward |
| S | Save / Unsave |
| P | Pin / Unpin |
| U | Mark as unread |

Copy link, Share to Outlook, Translate, Report, Immersive Reader and Read by have no shortcut.

---

## Unconfirmed
- The visual form of `actionMenuConfirmationConfig.showConfirmation()` after Copy link.
- Esc in the forward dialog.
- The RCM mapping for saving a reply (`mid` ≠ rcId → `sl2`).
- Whether the legacy L2 bookmark resolver subtracts 1 ms.
- The pinned banner timestamp format, and the effect of the info-pane `"closed"` call after pinning.
- The translation-settings roaming endpoint (`startLanguageAccountSettingsUpdateWorkflow`).
- The CSA path prefix `api/v1/` for translate (taken from the CSA transport constants, not from a captured request).
- Whether `allowCommunicationComplianceEndUserReporting` (inappropriate reporting) is on for this tenant, and whether any confirmation UI follows a successful V2 report.
- The exact `userReportedData` body wrapper.
- What the Outlook task-module web app shows.
- Any extra entries at the end of More actions.

## Corrections to `messages-and-composer.md`
- §13/§21 forward: the URL is `…/conversations/{originalConvId}/messages/forward`, with `targetThreadIds` in the body (not `{target}` in the URL).
- §13/§21 translate: CSA `{csa}/api/v1/chats/{id}/messages/languages/{lang}`, not the middle tier.
- §21 mark unread: the property is `consumptionHorizonBookmark` (L1), or RCM `chb` (L2), not `consumptionhorizon`.
- §21 pin: `PUT {chatsvc}/v1/threads/{id}/properties?name=pinnedItems`.
