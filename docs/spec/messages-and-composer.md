# Message timeline, hover bar, message menu, reactions and compose box — Teams desktop behaviour (spec)

Source: the Teams client itself (build 26276.513, Windows desktop). Its
modules were read from the published client bundles and from the data-layer
web worker (`precompiled-web-worker-inner_*.worker.js`). Module ids are given
so this can be re-checked against later builds. Strings are the en-us texts.
They were resolved from Teams' obfuscated string keys
(`k` + base36(poly131(`"ns:key"`) mod 2^40), module 263249), using the
locale store of the running app.

"Live" values are tenant settings read read-only from the running Windows app
on winpc (signed in as ost-test1) through `coreSettings.get(category)`. Every
setting is named so the defaults can be compared. The running window showed a
channel Page tab during this work, so no message list, hover bar or compose box
was in the DOM. All layout numbers therefore come from the code and its
Griffel CSS (Teams sets `1rem = 10px`), not from measuring the live window.

---

## Components (module index)
| area | module(s) |
|---|---|
| Timeline item pipeline: grouping, dividers, read-receipt status | 434910 (`Vt` → `wt` → `jt`), item types 991060, type→item 117701, control test 770846, message types 201110 |
| Chat message renderer (avatar, header, bubble, tombstone, hover popover) | 318259 |
| Comfy message layouts | 299246 (others, `ChatMessage`), 299320 + styles 213860 (own, `ChatMyMessage`); compact 268752 |
| Timestamp formatting | 221891, formats 494393, constants 59423 |
| "Last read" divider, jump buttons | 497560, 210311 |
| Control/system message strings | 75579 |
| Message states (edited, failed, important) | 436560, 533020, 924964, 4584 (undo delete), 317519 (failed-message actions) |
| Typing indicator | 866494, 924321; worker inner_c / inner_d |
| Channel post reply summary | 693292, 661183 |
| Hover toolbar | chat 318259 (`qc`/`Vl`), channel 456275, action list 344274, buttons 706871, quick reactions 547607/585676/348213 |
| Right-click menu | 736982 |
| Message ··· menu | 629737 (registry `Ui`, `$i`/`Mt`/`Wt`), context 185439, chat permissions 263162, channel permissions 236668 |
| Reactions | summary 226455, channel wrapper 1975, mutation 21117, toggle 573742, limits 217146, who-reacted 833469, picker 940673/205928 |
| Compose box | 266342 (simplified compose), 899468 (classic toolbar), 111774 (formatting bar), 332416 (send/post), 930874 ("+" flyout), 916609 (attach), 505584 (fun picker), 648927/871091 (delivery options), 920642 (schedule send), 198077 (pre-send checks), 930187 (@mentions) |
| Keyboard shortcuts | 504800 (Windows keymap class `P`), lookup hook 714901 |

---

## 1. Timeline: what gets rendered (434910)
- Messages are de-duplicated by `from + (clientMessageId || id)`. When
  `enableContentHashAsMessageDedupeKey` is on, `_contentHash` is added to the key.
- The array is processed **newest first**. The list renders
  `orientation:"bottom-up"` (324895).
- Item types (991060):
  `ConsumptionHorizon=0, Control=1, Divider=2, Message=3, RecordingMessage=4, TranscriptMessage=5, LocalRecordingMessage=6, SmartCard=7, MeetingOrientationSmartCard=8, FollowedMeetingTopicsCard=9`.
- Any `messageType` matching `/^(Event|Control|ThreadActivity)/` is a control
  message (770846).
- **Visible message types** (`Lt`, wire names from 201110):

| chat kind | visible types |
|---|---|
| 1:1 (`st`) | `Text, RichText, RichText/Html, RichText/Contacts, RichText/Files, RichText/Sms, RichText/Location, RichText/Media_Card, Collaborate, ThreadActivity/ConsentInvites, Embed, ThreadActivity/FileAdd, RichText/Media_AudioMsg, RichText/UriObject, RichText/Media_GenericFile, RichText/Media_Video, Poll, RichText/ScheduledCallInvite, SmartCard, Event/Call, RichText/Media_CallRecording, RichText/Media_LocalRecording, RichText/Media_CallTranscript, ThreadActivity/MessageMoveStarted, ThreadActivity/MessageMoveCompleted` |
| group (`Ke`) | the 1:1 set plus `ThreadActivity/AddMember, CreateThread, DeleteMember, TopicUpdate, PictureUpdate, ThreadShared, ImmersiveStarted` |
| meeting (`bt`) | the group set plus `ThreadActivity/MemberJoined, MemberLeft, MemberRenamed, OriginalDisplayNamesRestored, MeetingPolicyUpdated, RichText/Media_MeetingObjects` |
| threaded (ConvUX) channel | also `ThreadActivity/ModalityUpdate` |
| any | `ThreadActivity/ShowChatHistory`; `AddCustomApp/DeleteCustomApp` when `enableAppControlMessages` is on |

- **Always hidden**:
  - `ThreadActivity/PinnedItemsUpdate`.
  - Messages that are only whitespace and have no files.
  - A deleted message, unless one of these is true: `deletionInfo.canBeUndeleted`, `isDeletedByAdmin`, it was hard-deleted for data spillage, `deletionInfo.showMessageAsDeleted`, it has replies, or it is the open reply-chain root.
  - A deleted targeted message.
- **Synthetic rows**:
  - `retention_deleted` → "We've deleted older messages due to your org's retention policy. Learn more".
  - `partial_history` → "You won't see messages that were sent before you joined the chat."
  - Smart card at the "Last read" position.
  - Meeting orientation card.
  - Followed-topics card.

## 2. Grouping ("attached") (434910 `mn`, `En`, `Tn`)
- **Threshold: 5 minutes** (`Ot = 5` × `Kv = 60000` ms). A message joins the
  previous one when
  `cur.originalArrivalTime − prev.originalArrivalTime ≤ 5 min`.
  The check is between **consecutive messages**, not against the first message
  of the group, so a group can go on indefinitely.
- **A group breaks** when any of these is true:
  - the current message is pending (Sending/Retrying), unless auto-send is on (`enableAutoSendV2`, live true);
  - the sender (`from`) differs;
  - either message is a control message;
  - a bot sends on behalf of a different person (`onBehalfOf` with `mentionType:"person"`);
  - `appMetaData.id` differs;
  - either message is `RichText/Media_CallRecording`;
  - `sharedFromMessageId`/`sharedToMessageId` is set;
  - either arrival time is missing;
  - in chats (and in threaded channels with `enableReplySummaryPostDetachmentInThreadedChannels`, live true), either message has replies;
  - **a date divider or the "Last read" divider falls between them** (`isShortIntervalSend: !dividerPresent && mn(...)`).
- **`attached` value** (`En`):

| value | meaning |
|---|---|
| `false` | standalone. Also forced when this message or its neighbour was deleted by an admin or for data spillage |
| `"top"` | first message of a group |
| `true` | middle of a group (rendered as `"center"`, 318259 `ni`) |
| `"bottom"` | last message of a group |

  `bubbleAttached` also splits a group where a single image without a bubble
  sits next to a normal bubble (`Dt`).
- **Header visibility**:
  - **Author name**: shown only when `attached` is `false` or `"top"` (299246). On **own messages it is always screen-reader only**, so no name is visible (299320).
  - **Avatar** (others only, 318259 `_p`): shown when `attached ∉ {true, "bottom"}`. In comfy density it is never shown on own messages. Also hidden for admin- or spillage-deleted messages, in multiselect mode, and in a lobby chat for non-admins.
  - **Timestamp**, with `enableChatRefreshPersistentTimestamp` (live true): on the name line, visible only on `!attached || "top"`, and screen-reader only otherwise. With the flag off it sits beside the message and appears on hover/focus.

## 3. Layout and responsive widths (299246, 299320/213860, 318259; container queries)
- **Alignment**: others are left-aligned with an avatar column. Own messages
  are right-aligned (`justify-content:flex-end`) and have no avatar.
- **Vertical gap**: 12px padding-top at the start of a group, 2px inside a group.
- **Bubble**: radius `--borderRadiusLarge`, border `1px solid --colorTransparentStroke`,
  padding `6px 15px 8px`.
  - Others: `--colorNeutralBackground3`.
  - Own: `--colorBrandBackground2` (light), `#2B2B40` (dark).
  - Grouped corners: `top` → both bottom corners 0; `center` → all four 0; `bottom` → both top corners 0.
- **Text**:
  - Body: `--fontSizeBase300` (14px), `word-break:break-word`.
  - Name and time: `--fontSizeBase200`; time colour `--colorNeutralForeground3`.
  - Name line: flex, baseline-aligned, `column-gap:8px`, `margin-bottom:2px`.
  - Details ("Edited"): `--fontSizeBase100`, line-height 12px, gap 6px.
- **Max width** (by the width of the message-pane slot container):

| | root | body ≥480px | body ≥720px | without avatar/status: <480 / ≥480 / ≥720 |
|---|---|---|---|---|
| others | `calc(100% − 70px)` | `calc(100% − 142px)` | `calc(100% − 198px)` | `calc(100% − 54px)` / `−118px` / `−158px` |
| own | `calc(100% − 66px)` | `calc(100% − 142px)` | `calc(100% − 160px)` | `calc(100% − 52px)` / `−124px` / `−140px` |

- **Side margins**:
  - Others without an avatar: 16px / 24px (≥480) / 40px (≥720).
  - Own without a status icon: 14 / 18 / 58px; own with status: 38px at ≥720.
  - Avatar: 32×32 at ≥480; avatar column 16 / 24 / 40px.
- **Body `--width` variable**, by container width (rem ×10 = px):

| container | 0 | 240 | 290 | 320 | 360 | 375 | 414 | 480 | 640 | 720 | 768 | 834 | 947 | 1000 | 1024 | 1280 | 1350 | 1440 | 1500 | 1680 | 1920 | 2048 | 2560 | 3840 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `--width` (rem) | 11.3 | 11.4 | 16.4 | 19.4 | 23.4 | 24.9 | 28.8 | 26 | 42 | 44.4 | 49.2 | 55.8 | 67.1 | 72.4 | 74.8 | 100.4 | 107.4 | 116.4 | 122.4 | 140.4 | 164.4 | 177.2 | 228.4 | 356.4 |

  The values follow (breakpoint − offset)/10 with offsets 126 / 220 / 276
  (574122, 7260).
- With `enableResponsiveFwDeprecation` off (live: **on**, so this does not
  apply), 1:1 chats in comfy density hide avatars below 720px (`mi`).

## 4. Timestamps (221891; formats 494393)
- Formats:
  - `Hw` = hour:minute.
  - `yf` = weekday long.
  - `YQ` = day/month numeric.
  - `Gv` = d/m/yy.
  - `oJ` = day + month long.
  - `zc` = day + month long + year.
- **Date part `Yq`**:
  - today: "Today" only when `isTodayVisible`, otherwise empty (aria: "Today at");
  - yesterday: "Yesterday" (aria: "Yesterday at");
  - less than 7 days ago (`ZQ=7`): the weekday;
  - same year: `YQ` (`oJ` when long);
  - otherwise `Gv` (`zc` when long).
- **`r6`** = `"<date> <time>"`.

| where | format |
|---|---|
| message header (comfy, persistent-timestamp flag on, live) | `r6`: "10:32 AM", "Yesterday 10:32 AM", "Monday 10:32 AM", "11/6 10:32 AM", "11/6/25 10:32 AM". Compact, or flag off: time only |
| header tooltip / aria | "Today at 10:32 AM", "Yesterday at 10:32 AM", "November 6, 2025 10:32 AM" |
| control-message time | `r6` |

## 5. Dividers and jump buttons
- **Date divider** (`date_divider_<key>`, 434910 `yn`/`gn`; renderer 318259 `Wu`):
  - Placement: above the first message of each new local day (`toDateString()` changes).
  - With comfy density and persistent timestamps on (live), there is **no divider at the top of the list**. The between-groups divider (gap ≥ 1h, `qD = 3600000`) is also off; it is only added when persistent timestamps are off.
  - Text: `Yq`, i.e. "Today", "Yesterday", "Monday", "November 6", "November 6, 2025".
  - Style: Fluent Divider, NeutralForeground3, margin-top 12px. In comfy density both lines are transparent, so only the text shows.
- **"Last read"** (`ch_divider_<key>`, 434910 `pn`/`sn`; renderer 497560):
  - Placement: above the oldest message newer than the user's consumption horizon that is not a control message and not the user's own (unless the horizon is bookmarked). None when the horizon time is 0.
  - Rendering: Fluent Divider `appearance:"brand"`, `role=heading aria-level=3`, `data-tid="last-read-line"`, text **"Last read"**, bold, margin-top 12px.
- **Reply-summary divider** (threaded channel side pane): "{{replyCount}} reply" / "{{replyCount}} replies".
- **Floating buttons** (210311):
  - "Jump to last read" (`jump-to-last-read-button`, primary): shown while the "Last read" divider is off-screen.
  - "Jump to newest".
  - "New messages" pill, with the count of unread incoming messages.
  - "Recent".
  - A deep-linked message is highlighted for `deeplinkMessageHighlightDuration` (live 4 s).

## 6. Message states
| state | en-us text | condition / module |
|---|---|---|
| edited | **Edited** in the details slot; tooltip "Edited {{editTime}}" (e.g. "Today at 3:04 PM") | `editTime` set (436560) |
| bot/card updated | Updated / "Updated {{updateTime}}" | 436560 |
| deleted | **This message has been deleted.** (`data-tid="message-tombstone"`, muted, margin 1.2rem) | 318259 `_renderTombstone` |
| undo delete | **Undo** (transparent button `message-undo-delete-btn`) | only if `deletionInfo.canBeUndeleted` and the message is not scheduled, not targeted, and not Urgent (4584) |
| delete failed | Delete failed | 436560 |
| sending | Sending... / Retrying... (`message-sending-title`) | status Sending/Retrying and auto-send off (318259 `Rd`) |
| failed | "Failed to send." / "Failed to edit." / "Failed to send. Message too large." / "Message didn't send. Check your connection or try again later." | status Error/Undeliverable. Bubble `--colorPaletteRedBackground1`, border `--colorPaletteRedBorder1`, red icon (533020, 213860) |
| failed actions | Retry, Edit, Delete (`message-failed-retry`, `edit-restricted-message-button`, `message-failed-delete`) | 317519 |
| retry tooltips | "Retrying... Message delayed due to connection issues. Please check your network." / "Retrying... You've reached the current limit. Please wait a moment." | `enableSendPipelineEnhancedRetryTooltips` (live true) |
| importance | **IMPORTANT** / **URGENT** (CSS uppercase), semibold base200, `--colorPaletteRedForeground3`, plus an icon decoration | `importance ≠ "Standard"` (924964, 318259 `Yc`) |

## 7. Read receipts and delivery state (434910 `cn`/`un`/`fn`/`Ln`; 318259 `bc`; 298781)
- **Only one or two own messages carry a status icon**:
  - the newest own non-deleted message with status Delivered → `sent`;
  - the newest own message that has been seen → `seen` (1:1) or `seenByEveryone` (group).
  - Every other own message gets `none`, meaning **no icon**.
  - Pending messages show `sending`/`retrying`, scheduled ones `scheduled`, failed ones `failed`.
- **Seen rule**: `arrival ≤ min(other members' consumptionhorizon first field) && arrival ≥ max(their messageVisibilityTime)`. It is evaluated only once every other member has a horizon.

| status | tooltip | icon (12px; 16px ≥480; `--colorBrandForeground1`) |
|---|---|---|
| sending / retrying | Sending... / Retrying... | Circle |
| sent | Sent | CheckmarkCircle |
| seen | Seen | EyeFilled (animates when it changes from sent) |
| seenByEveryone | Seen by everyone | EyeFilled |
| failed | Failed | WarningFilled (red) |
| scheduled | Scheduled | Clock |

- Icon box: 12×12 (16×16 at ≥480), margin 2px (4px at ≥720), `align-self:flex-end`,
  tooltip below.
- **Enabled when** (worker inner_d `je`):
  - `enableReadReceipts` (live true);
  - `receiptsEnabledType ≠ "None"`;
  - **member count 2..20** (`maxRosterSizeInGroupChatChatServiceLimit`, live 20);
  - user preference `readReceiptsEnabled ≠ "false"`.
- Endpoint: `GET {chatsvc}/v1/threads/{id}/consumptionhorizons` →
  `consumptionhorizons[{id, consumptionhorizon:"arrivalMs;timestampMs;clientMsgId", messageVisibilityTime}]`.
  Live updates come as `ThreadActivity/MemberConsumptionHorizonUpdate`.

## 8. Typing indicator (866494, 924321; worker inner_c `DP`, inner_d `mS`)
- **Text** (`tmp_messages_typingIndicator_mf`):
  - 1 typer: "X is typing"
  - 2: "X and Y are typing"
  - 3: "X, Y, and Z are typing"
  - more than 3: "X, Y, and N others are typing", where N = count − 2
  - Every variant starts with a leading space.
- **UI**: `data-tid="typing-indicator"`, small text with an animated ellipsis, fades in and out.
  - It stays **3000 ms** after the typer list empties.
  - An avatar shows only when the typer is a bot.
  - Hidden in thread panes, in channels (except bots in L1 with a flag), when `disableTypingIndicator` is set, and above 20 members.
- **Receive**: `Control/Typing` adds the user until
  `originalarrivaltime + typingIndicator.userTimeout` (live **22000 ms**). Any
  other message from that user (for example `Control/ClearTyping` or a real
  message) removes them.
- **Send**: `sendTypingIndicator(convId)` → `POST …/conversations/{id}/messages`
  with `{content:"", contenttype:"Application/Message", messagetype:"Control/Typing"}`.
  - Throttled per conversation, leading edge only, once per `typingIndicator.notificationFrequency` (live **20000 ms**; default 6000).
  - Not sent while editing, in reply chains, or when members are ≤1 or >20.

## 9. System / control messages (75579)
`<0>` is the actor (rendered as a bold, clickable persona); `<1>`/`<2>` are
targets. With three or more targets the text reads `<1> and {{otherTargets}}`,
where `{{otherTargets}}` = "# other" / "# others" and n = targets − 1.

| wire type | en-us text |
|---|---|
| AddMember | `<0> added <1> to the chat.` / `<0> added <1> and <2> to the chat.` / `… and {{otherTargets}} …` |
| AddMember with history | `… to the chat and shared all chat history.` (days = 0) / `…from the past day.` / `…from the past # days.` (days = round((eventTime − shareHistoryTime)/86400000)) |
| DeleteMember (self) | `<0> left the chat.` |
| DeleteMember | `<0> removed <1> from the chat.` (plus the two- and many-target forms) |
| DeleteMember by the system | `<0> was removed from the chat.` / `<0> and <1> were removed…` |
| TopicUpdate | `<0> changed the group name to <1>.`; empty name: `<0> removed the group name for this conversation.`; meeting: `<0> named the meeting <1>.` |
| PictureUpdate | `<0> changed the group profile picture.` |
| MemberJoined | `<0> joined the conversation.` (meeting: `was invited to the meeting.`, `has temporarily joined the chat.`, lobby `is in the lobby.`) |
| MemberLeft | `<0> no longer has access to the chat.` (meeting: `left the chat.`) |
| pin / unpin | `<0> pinned a message.` / `<0> unpinned a message.` |
| ConsentInvites | `<0> won't be added to the chat until the message is accepted.` |
| MemberRenamed | `<0> changed their display name to <1>.` |
| ThreadShared | `<0> invited <1> people to the group. Invited members will not see any history until they join Teams.` |
| ShowChatHistory | Show hidden chat history |
| MeetingPolicyUpdated | Chat has been turned on/off for this meeting. |
| ModalityUpdate | The layout was changed to posts. / …threads. |
| ReplyChainCreated | `<0> started a thread.` |
| Event/Call, started | Call started / Meeting started / Screen share started; huddle: `<0> started a meeting.` / You started a meeting. |
| Event/Call, ended | Call ended / Call missed / Meeting ended: / Screen share ended |
| recording / transcript | "Recording has started", "{{initiator}} started recording.", "Recording stopped. Saving recording…", "Recording has been saved to {{owner}}'s OneDrive", "Recording stopped and wasn't saved as it was too short.", "Transcription has started", "Transcript has been saved to OneDrive" |

- **Call-ended row** (75579 `$a`): `<time>` + EM SPACE + text + NBSP + **bold duration**.
  - The duration is `{h}h {m}m {s}s` with zero parts dropped.
  - There is no duration for a missed call (ended, not a meeting, fewer than 2 participants in `<partlist>`).
  - The row is not rendered when there is no duration or no participants.
  - aria: "Call ended at {{time}} after {{fullDuration}}".
- Recording rows read "{{message}} at {{time}}".
- An Event/Call row counts as ended when the content has `<ended/>` or `partlist type="ended"` (197100).

## 10. Channel posts and replies
- **Subject**: `h2 data-tid="subject-line"`, 18px semibold, max-width 1028px,
  padding-bottom 16px (8px in the threaded view). The subject field in compose
  allows 250 characters.
- **Reply summary on classic (post/reply) channels** (693292 `Fs`, `response-summary-button`):
  - Text: "Open {repliesCount} replies from {user1}[, {user2}][ and {user3}][, and # others]", naming at most 3 repliers.
  - There is **no singular form**: one reply reads "Open 1 replies from …".
  - The current user is named "you", unknown users "Unknown", and names are cut at 50 chars + "...".
  - Bold when there are unread replies (hidden text "New replies"). Mention, importance and attachment icons follow it.
- **Bottom of a classic post**: the current user's avatar plus a collapsed
  **"Reply"** compose. The threaded variant reads "Reply in thread". When
  replying is blocked it shows a disabled text instead, e.g. "You've been
  muted, so you can't reply."
- **Threaded (ConvUX) channels** (318259 `nl`/`sl`):
  - Avatars of the recent repliers.
  - A link "# reply" / "# replies" in `--colorBrandForegroundLink`, bold when unread.
  - Mention, important and urgent badges.
  - "Last reply {{timestamp}}": time only if under 24h ago, otherwise the date.
- **New post**: the button reads **"Post in channel"** ("Start a new
  announcement" for guardians). See §16 for the post compose.
- **Announcements** are rendered only in threaded channels
  (`enableConvUXAnnouncementsAndTitle`, title or `croppedImageUrl`, component 598599).

---

## 11. Hover toolbar (chat 318259; channel 456275; actions 344274/706871)
- **Chat**: a Fluent Popover per message (`data-tid="message-actions-container"`).
  - Opens on hover (`openOnHover`). `mouseLeaveDelay: 0` with a 1500 ms pointer safe zone (`Xc`).
  - Position: above, aligned end, pinned, no autosize (compact density: mainAxis −4). Closes on scroll.
  - Content: a small Fluent Toolbar with aria "Reactions and message actions". Right-click on it is swallowed.
- **Channel**: popover `channel-message-action-menu`, `mouseLeaveDelay: 100`,
  opened by `onMouseMove` or focus.
- **Shown only when**:
  - the user is a member and the message type is allowed;
  - not deleted, not in a pending or blocked chat;
  - status Delivered (or failed with offline actions on);
  - not mid-move;
  - not in a lobby chat for non-admins;
  - the right-click menu is not open, no other popover is open, and multiselect is off.
  - Channels also need the message not to be pending (`id === clientMessageId`).
- **Order, left to right**:

| # | data-tid | label | shown when |
|---|---|---|---|
| 1..n | `message-actions-{key}` | emoji title, e.g. "Like" | `canReact`, reactions not disabled, not a targeted message |
| n+1 | `expanded-reactions-picker-entry` | More reactions | same |
| — | vertical divider | — | after the reactions |
| a | `message-hover-action-edit` | Edit (tooltip shows E) | action list contains `edit` |
| a | `message-hover-action-quoted-reply` | Reply with quote | list contains `reply` and `canReply` |
| a | `message-hover-action-threaded-reply` | Reply in thread (disabled tooltip "A thread can’t be started from this chat.") | list contains `threaded-reply` |
| b | `message-hover-action-send-to-copilot` | Ask Copilot | `enableSendToCopilotInHoverToolbar` (live absent, so off) |
| c | `message-actions-more` | More options | always; opens the ··· menu (§13) |

  The action buttons (rows a and b) need `enableActionsInHoverMenu` (chat, live
  true) or `enableActionsInHoverMenuInChannels` (live true).
- **Action list** (344274). T = threading available (445473; in channels ConvUX
  only; in chats `enableThreadCreationChat`, live false, or the chat is
  threaded):

| case | own message | someone else's |
|---|---|---|
| no threading (classic channels, normal chats) | Edit | Reply with quote |
| thread pane (L2) | Reply in thread + Edit | Reply with quote |
| threaded channel | Reply in thread + Edit | Reply in thread |
| threaded chat | Reply in thread + Edit | Reply in thread + Reply with quote |

- **Quick reactions** (547607):
  - The list comes from user preference `defaultMessageReactions`. If unset, the ECS `defaultMessageReactions` is used (live `["like","heart","laugh","surprised"]`; the code fallback is the same four).
  - While the preference loads, the legacy six are shown: like, heart, laugh, surprised, sad, angry.
  - "like" takes the preferred skin tone (`yes-tone{N}`).
- **Customising reactions** (249154; needs `enableCustomizeReactions`, live true):
  - The dialog has 5 slots. Title "Customize your reactions & appearance in Teams", with a skin-tone radio and Save/Cancel.
  - Saved with `updateUserPreferences(category:"defaultMessageReactions")`.
  - Entry point: "Customize default reactions" in the picker header.
- **Reaction button state** (348213):
  - The button is `aria-pressed` (underlined) when the user already reacted with it.
  - At the 20-reaction limit the tooltip becomes "You’ve reached the {{limit}}-reaction limit. Remove one to add another." and the click is refused.
  - A click toggles the reaction and closes the popover.
- **Keyboard**:
  - Focusing a message opens the popover. Enter moves to the first reaction; Esc closes.
  - The hidden button "More message options" toggles the popover.

## 12. Right-click (736982, 629737 `ft`)
- The message is wrapped in a context menu. It is not offered for lobby chats
  (non-admin), pending channel messages, deleted messages or locked messages.
- When text is selected, the **native** context menu is used instead.
- Opened with the right mouse button, the menu sits at the pointer; otherwise
  it is anchored to the message.
- It shows the same items as the ··· menu, with these differences:
  - When `enableRightClickReaction` (live true) and `canReact`, the reaction strip (`message-reactions-on-menu`) is added on top, followed by a divider.
  - It does **not** remove the hover-bar actions, so Edit, Reply with quote and Reply in thread stay in the list (see §13).

## 13. The message ··· menu (629737; context 185439; permissions 263162 chat, 236668 channel)

### Where the item list comes from
- The context provider (185439 `rX`) gets a `messageContext`: `Chat`,
  `FlyoutInlineChat`, `ChannelPost`, `ChannelReply`, `DiscoverSurfacePost` or
  `PinnedPostCard`. It reads `core` and `secondary` id lists from the setting
  `msgActionsMenuActionsConfig` (Messaging), with a built-in default `w` in
  185439. **Live** value:

| context | core (configured) | secondary (configured) |
|---|---|---|
| Chat | edit, threaded-reply, reply, copy-link, save, reminder, delete, unshare-message, read-receipt, pin, forward, delete-bot-message, ask-copilot, thread-summarization | share-to-outlook, report-a-concern, report, immersive-reader, translate, unread, escalate, refresh |
| ChannelPost | edit, threaded-reply, reply, follow, forward, copy-link, save, reminder, pop-out, delete, unshare-message, pin, highlights, mute-post, thread-summarization, delete-bot-message, ask-copilot | share-to-outlook, report-a-concern, report, immersive-reader, translate, unread, refresh |
| ChannelReply | edit, reply, forward, copy-link, save, reminder, delete, delete-bot-message, ask-copilot | same as ChannelPost |
| FlyoutInlineChat | edit, threaded-reply, unshare-message, reply, delete | unread, translate, report |

- **The on-screen order is the registry order, not the configured order.**
  `Qo(config, registry) = registry.filter(a => config.includes(a.id))`. The
  registry `Ui` (629737) is:
  `threaded-reply, bypass-stuck-action, reply, edit, forward, follow, copy-link, reply-with-copilot, save, reminder, delete, unshare-message, delete-bot-message, pin, mute-post, unread, send-to-copilot, ask-copilot, share-to-outlook, report-a-concern, translate, immersive-reader, read-receipt, debug, refresh, pop-out, discover-surface-block-post(-user,-channel), highlights, report, remove-member, thread-summarization`.
  Configured ids that are not in the registry (such as `escalate`) are dropped.
- Each item component checks its own condition and renders `null` when it
  fails: the item is **hidden, not disabled**, unless the table below says
  disabled.

### Menu layout (`$i` → `Mt` → `Wt`)
1. **Reaction strip**: right-click only (`isOpenedFromRightClick` and `enableRightClickReaction`).
2. **Core items** in registry order. In a lobby chat only `edit` and `delete` are kept.
   - Opened from the hover bar's ··· (`isRenderFromMoreActionsMenu`) with `enableActionsInHoverMenu` on, the actions already on the hover bar (§11 table) are **removed**.
   - The right-click menu keeps them.
   - `highlights` is removed when there isn't enough content for a summary.
3. **Divider** (`l1-secondary-divider`, only when there are both core items and L1 secondary items), then the **first 3 secondary items** (`msgActionsL1MenuSecondaryActionsCount`, live 3; code default `ji = 3`).
   - With `enableAppActionsUsageRendering` (live true), the secondary list (1st-party items passing `shouldRender`, plus app/message-extension actions) is **sorted by the user's recent action usage**.
   - The sort is a stable `sortBy` on the usage index (944309 `q$`), so items never used keep registry order. `report-a-concern` is excluded from sorting.
   - Every click is recorded with a GraphQL usage mutation (`enableAppActionsUsageRecording`).
4. **Chats only**: when `allowUserTranslation` and (`enableTranslationOverflowMenuV2` with the message already translated, or `enableTranslationIntelligentSuggestions`; both live true), a **"Translation"** submenu (opens on hover) replaces the plain Translate item. Its items (339225), in order:
   - "Translate" or "See original message ({{originalLanguage}})"
   - "Turn on auto-translation" (chat, auto off, message not in the preferred language)
   - "Never translate {{language}}"
   - "Settings"
   - "Give feedback" (behind a flag)
5. **Divider** (`report-concern-option-divider`), then **"Report this message"** (report-a-concern, raised to the top level by `enableReportAConcernOnTopLevel`, live true).
6. **Divider** (`more-option-divider`), then **"More actions"**, a submenu that opens on hover.
   - Contents: the rest of the secondary items (L2), then app actions.
   - Shown when `canHaveL2Menu && canShowApps`. Not shown in the simplified flyout chat, with `disableContextMenuMoreAction`, or in a lobby chat.
   - **Disabled** (not hidden) when L2 is empty.
7. Developer mode only: Copy Message ID / Copy CDL Key / Copy User ID / Copy Message Content.

### Items
| id | label (en-us) | data-tid | shown when | action / service |
|---|---|---|---|---|
| threaded-reply | Reply in thread | message-actions-threaded-reply | threading on and not in the thread pane (445473 `R`), plus `canThreadedReply`. **Disabled** (tooltip "A thread can’t be started from this chat.") when `disableThreadedReply` | opens the thread pane. **T** |
| reply | **Reply with quote** (`enableNewQuotedReplyIcon`, live true); else "Reply" | message-actions-quoted-reply | `canReply`, not `isReplyDisabled`, not a meeting object in a threaded group chat (435636). Chat: member, not a Copilot chat, not a system message, reply policy not Disabled. Channel: ConvUX channels with `enableConversationalChannelsQuotedReply` only | quotes the message into the compose box (777538). **Q** |
| edit | Edit | message-actions-edit | **own message only**. `allowUserEditMessage` and `canEdit`; not audio, Fluid/Loop, deleted, **Urgent**, a message with deeplinks, a failed file upload, a message being moved, or a meeting/call message in a channel; no inline `<video>`; not shared from a thread (579903 `O`). Channel: team/space `editMessagesEnabled` (null = allowed), team not archived, user not muted, not an email post (236668 `x`). Chat: status Delivered, or offline edit allowed. **No time limit anywhere.** **Disabled** when offline without offline edit | edit in place. **E** |
| forward | Forward. With multiselect it is a split button ▸ "This message" / "Multiple messages" (aria "Forward options") | message-actions-forward… | `canForward`, `enableForwardMessage` (live true), forwardable content. **Disabled** above `maxForwardMessageImageCount` (live 5) images, with tooltip "Forwarded messages have a combined image limit of {{maxForwardMessageImageCount}}. This message would exceed that limit." Multiselect: chat yes (live), channel no (live) | forward dialog; `POST …/conversations/{target}/messages/forward`. **F** |
| follow | "Follow thread" / "Unfollow thread" (ConvUX channels + SimpleCollab on, live); otherwise "Turn on notifications" / "Turn off notifications". "New" badge until seen | — | channel post, `canFollow` (`enableThreadedChannelFollowUnfollow` / `enablePostReplyChannelFollowUnfollow`, live true), follow state known, not shared from a thread | follow/unfollow the reply chain |
| copy-link | text always **"Copy link"**; title/aria "Copy message link" / "Copy reply link" / "Copy post link" | message-actions-copy-link | not sending, `canCopyLink` (chat: member, not pending, copying not blocked; private/shared channels need their flags, live true). Hidden for scheduled chat messages and in meeting chats on `thread.tacv2`/`thread.skype` | copies the deep link; announces "Copied to clipboard" |
| save | "Save this message" / "Unsave this message" (tooltip when saved: "Saved by you. Others won't see that it was saved.") | message-actions-save | `canSave` (member), saving enabled, not the notes-to-self chat. **Disabled** offline | `setReplyChainSaveState` → `PUT /v1/users/ME/conversations/{conv}/rcmetadata/{replyChainId‖messageId}` with body `{s, mid}`; announces "Message saved"/"Message unsaved". **S** |
| reminder | Remind me ▸ Now / Later today / Tomorrow / Next week / Custom (or Edit reminder / Remove reminder) | — | `enableRemindersSlice` (live **false**) | `createOrUpdateMessageReminder` |
| delete | Delete (title "Delete this message") | message-actions-delete | `canDelete`, not unshareable (862660 `P`). Chat: own message with `allowUserDeleteMessage` and not Sending, or chat-admin/owner delete rules (263162). Channel: own message with `deleteMessagesEnabled` (null = allowed), or team Admin with `adminDeleteEnabled`; never in archived teams or for muted users (236668 `j`). **Disabled** offline unless auto-delete is on | **deletes at once with no confirmation dialog**; the row becomes the tombstone with **Undo**. `DELETE …/messages/{id}?behavior=softDelete`. Undo: `DELETE …/messages/{id}/properties?name=deletetime`. Cross-posts open the cross-post delete dialog instead. **Del** |
| unshare-message | "Remove from chat" / "Remove from channel" | message-actions-unshare-message | `enableShareThreadRepliesToL1` (live true) and the message is a thread reply shared to the main view | `unshareThreadReplyMessage` |
| delete-bot-message | Delete | — | sender is a bot or agent | delete + feedback prompt |
| pin | **"Pin for everyone" / "Unpin for everyone"** | message-actions-pin | `canPin`; not 2-way SMS; not shared from a thread; ChannelReply only with the CSA API (987814). Channel: `enablePinPost`, moderation allows it, nothing archived (236668 `i`). **Disabled** offline | `setPinnedItemsThreadProperty` / `chatPinUnpinPinbarMessage`; opens the chat info pane. **P** |
| mute-post | "Turn off notifications" / "Turn on notifications" | post-actions-mute | `enableMutePostInChannel` and not `enablePostReplyChannelFollowUnfollow`. **Live: hidden** (follow replaces it) | — |
| unread | Mark as unread | message-actions-unread | Chat: always (thread pane only with a flag, live off). Channel: L1 post with `enableL1MarkAsUnread` (live true) | `markMessageAsUnread(convId, replyChainId, messageId)`; announces "Message marked as unread". **U** |
| ask-copilot | Ask Copilot | message-actions-ask-copilot | Copilot license; delivered text/HTML/card with text | — |
| share-to-outlook | Share to Outlook | message-share-to-outlook | copying not blocked, `shareToOutlookConfig.enabled` (live true, app `40517485-2262-4135-b174-401da4aa6f0f`), no inline video | opens the Outlook app ("Outlook" / "Share conversation over email"); 20 s load timeout |
| report-a-concern | **Report this message** (else "Report a concern") | message-report-a-concern | someone else's message, member, not federated, no DLP violation, and one of: inappropriate (`reportAConcernConfig` + `allowCommunicationComplianceEndUserReporting`), security risk (`enableReportingAsSecurityRisk` + `allowSecurityEndUserReporting`, live on), wrong detection | report dialog |
| translate | Translate / See original message | message-actions-translate | `allowUserTranslation`, `msgEnableMessageTranslate`, on-demand V1/V2; not audio, Fluid, card or inline video. **In chats replaced by the Translation submenu** | middle tier `POST chats/{id}/messages/languages/{lang}` |
| immersive-reader | Immersive Reader | — | `allowImmersiveReaderV2` (live true), has content, not audio/Fluid/video/DLP, sender not a bot | Immersive Reader |
| read-receipt | "Read by {{membersCount}} of {{total}}" ("No receipt info available") ▸ list of readers (click opens a 1:1 chat) | — | **own message in a group chat** (not 1:1, not a meeting, not in the thread pane, not Fluid). **Disabled** when nobody has read it | — |
| refresh | Refresh card | — | MediaCard messages | — |
| pop-out | "Open conversation in new window" / "Open thread in new window" (threaded) / "Open in new window" (unified flag) | pop-out | `allowPostPopout` (live true), not the web client | new window |
| highlights | Highlights from this conversation | — | Copilot; only when thread summarization is off | — |
| report | Report a concern (own divider) | message-actions-report | `customerAdHocAbuseReport` (live **false**) | — |
| thread-summarization | Summarize thread | message-actions-thread-summarization | reply chain long enough, flags on | thread pane with summary |

### Effective menus on this tenant (live flags; Copilot and app items left out)
- **Chat, own message, ··· from the hover bar** (threading off; Edit is on the bar):
  - Core: Reply with quote, Forward, Copy link, Save this message, Delete, Pin for everyone, Read by N of M (group chats).
  - Then a divider and the L1 secondary items, then Translation ▸, then a divider and **More actions ▸**.
- **Chat, someone else's message, ···** (Reply with quote is on the bar):
  - Core: Forward, Copy link, Save this message, Pin for everyone.
  - Then a divider and the L1 secondary items, then Translation ▸, then a divider and Report this message, then a divider and More actions ▸.
- **L1 secondary for a user with no usage history**:
  - The ids that pass `shouldRender`, in registry order, are `unread, share-to-outlook, translate, immersive-reader[, refresh]`, and the first 3 go to L1.
  - **In chats `translate` takes a slot but renders nothing**, because the Translation submenu replaces it. So chat L1 shows only **Mark as unread, Share to Outlook**, and **Immersive Reader moves into More actions**.
  - In channels L1 shows Mark as unread, Share to Outlook, Translate.
- **Classic channel post, ···**:
  - Core: Forward, Follow thread, Copy link, Save this message, Delete (own post or admin), Pin for everyone, Open conversation in new window. "Reply in thread" never appears (threading is ConvUX-only in channels); Edit (own post) and Reply are on the hover bar.
  - Then the L1 secondary items, Report this message, More actions ▸.
- **Right-click**: the same menus with the reaction strip on top, and Edit / Reply with quote / Reply in thread kept in their registry slots.

## 14. Reactions under a message (226455, 1975, 21117, 573742, 217146, 833469)
- **Data**: `diverseEmotions.items[] {commonKey, count, emojiIdList, currentUserReaction, users[{userId, emotionKey, time}]}`.
  - `commonKey` drops `-tone\d`.
  - Server key "like" corresponds to the emoji asset "yes".
  - Names: Like / Heart / Laugh / Surprised / Sad / Angry, otherwise the emoji metadata description.
- **Summary**: `diverse-reaction-summary`, aria "Reaction summary". Chat: only if
  there are reactions and the message is not deleted. Channel: 1975.
- **Pill** (`diverse-reaction-pill-button`):
  - A small circular secondary ToggleButton, `checked` when the user reacted.
  - Up to 3 emoji variants (skin tones, the user's own first).
  - The count shows only when > 1, bold when it includes the user's reaction.
  - aria "{n} {reactionName} reaction(s)."
  - Click toggles: it removes the user's exact id, or adds it with the user's skin tone.
  - Right-click opens the who-reacted list.
- **Order**: pills with the user's reaction first, by count descending, then
  the rest in item order.
- **Overflow** (`Ze`):
  - Slot count is `overflowAfter` (chat live 5; classic channel 100; ConvUX channel uses the chat value) when width ≥480, otherwise 3; one fewer below 360 when the add button is present.
  - The width budget is slots × 36px. Pill width estimate: n_emoji×20 + 4 + digits×8 + 14 (a single pill is 34px).
  - The overflow button `diverse-reaction-overflow-button` reads **"+N", where N = the sum of the hidden counts (people), not the number of emoji**. It opens a hover menu "More reactions".
- **Who reacted**:
  - A hover menu (300 ms delay, below, offset 4) with **no per-emoji tabs**, titled with the reaction name.
  - Rows are 32px, list height min(n×32, 236)px.
  - Each row: avatar, name, and the emoji (for diverse or overflow lists); newest first.
  - Clicking a row opens a 1:1 chat.
  - On your own row, Delete/Backspace removes your reaction ("Delete your reaction (Delete)").
  - If the count doesn't match the loaded users, more are paged in through `messageAnnotations`.
- **Add-reaction button** (`add-reaction-picker-entry-point-button`, tooltip "More reactions"):
  - Chat: after the pills when `enableMultipleReactionsPerUser` (live true).
  - Channel: on posts only (not replies) when `enableAddReactionInReactionSummary` (live true); it shows even with zero reactions.
- **Limits**:
  - With multiple reactions per user, a user can add up to **20 distinct reactions**. Picking another skin tone of an emoji replaces the old tone.
  - With the flag off, a user has one reaction (`replace=true`).
  - HTTP 413/400 → banner "Current message size limit reached. We can't add any more reactions."
  - `canReact` is false in archived teams, for scheduled messages and for targeted messages.
- **Picker** (940673/205928):
  - Search "Find something fun".
  - Tabs: Recent (roams via `recentReactions`), Smilies, Hand gestures, People, Animals, Food, Travel and places, Objects, Activities, Symbols (+ Custom).
  - Metadata: `{statics}/evergreen-assets/personal-expressions/v1/metadata/{emoticonAssetVersion}/{locale}.json`.
  - Right-click a diverse emoji for 6 skin tones. Emoji tooltips appear after 1500 ms.
- **Service**:
  - GraphQL `updateMessageEmotion(convId, messageId, key, action:"add"|"remove")`.
  - Add: `PUT {chatsvc}/v1/users/ME/conversations/{conv}/messages/{id}/properties?name=emotions[&replace=true]` with body `{"emotions":{"key":"<key>","value":<epoch ms>}}`.
  - Remove: `DELETE` on the same URL with body `{"emotions":{"key":"<key>"}}`.
  - Who reacted: `GET v1/threads/{conv}/messages/{id}/annotations?filter=Type&value={key}&pageSize=100`.
- Note: the `expandedReactionsConfigs.summaryStyle` value ("bubble"/"flat") is
  read only by an unexported hook in 185439, so it has **no visible effect** in
  this build.

---

## 15. Compose box (266342 simplified compose; 899468 classic)
- `enableSimplifiedCompose` (live **true**) → the **simplified** compose (`rr`) is used.
- **Single-line state**: the editor sits in a row with a **side toolbar** on its right (`sendMessageCommands-*`).
- **Multiline state**: the side toolbar goes away and a **bottom toolbar** appears under the editor (`simplified-compose-bottom-toolbar`, `newMessageCommands-*`).
  - It switches to multiline when the formatting bar is expanded, there are files or cards, there is block content, or the text wraps (IntersectionObserver / chars-per-line estimate, 461103).
  - It switches back when the editor is empty and has no files or cards (458473).
- **Toolbar buttons, in order** (the same list feeds the side and bottom toolbars):

| # | id (data-tid suffix) | label | shown when |
|---|---|---|---|
| 1 | `expand-compose` | Show Formatting options / Hide Formatting options (Ctrl+Shift+X) | always |
| 2 | `UnifiedFunPicker` | Emoji, GIFs and Stickers | `enableUnifiedFunPicker` (live true) and emoji, Giphy or stickers allowed. Flag off: separate "Emoji", "Giphy", "Sticker" buttons |
| 3 | `FilePicker` | Attach files (tooltip "{{title}} (Alt+Shift+O)") | `enableAttachFilesInSimplifiedCompose` (live true). Flag off: Attach moves to the end group before Send |
| 4 | `open-compose-copilot` | Write with Copilot | Copilot compose gate passes |
| 5 | Loop | Loop components; with text present "Make this collaborative" | `enableStrategicAppsForSimplifiedCompose` (live true), Loop allowed, not editing |
| 6 | `message-extension-flyout-command` | Actions and apps ("+") | `enableMEFlyoutButton` (live true), not anonymous |
| end | `send` | **Send**; **Done** while editing (preceded by `discard-draft` "Cancel"); "Send with Copilot assistance" button before it when that feature applies | always |

- **No auto-overflow in the simplified compose**: only the empty `main`
  placeholder group has autoOverflow (410660), so these buttons never collapse.
- The **classic toolbar** (simplified compose off) is a different set, with auto-overflow titled "Messaging extensions":
  - Main group: Format, "Set delivery options", Emoji/Giphy/Sticker, Attach, Loop, Copilot, "Schedule a meeting", "Meet Now" (channel reply), message extensions.
  - Then the video clip camera.
  - End group: [Cancel edit], Send.

## 16. Formatting bar (111774, `simplified-formatting-toolbar`; shown when expanded)
Groups are separated by dividers; empty groups are skipped.

| group | items |
|---|---|
| 1 | Bold, Italic, Underline, Strikethrough |
| 2 | Bulleted list, Numbered list |
| 3 | Text highlight color, Font color, Font size |
| 4 | Quote, Insert link, Code block (`enableCodeBlockTopToolBarButton` live 1; "Code snippet" only when `disableCodeSnippet` is off) |
| 5 | [Announcement: new channel post only, not editing], Rich style, Code (inline), Clear all formatting |
| 6 | Decrease indent, Increase indent |
| 7 | Insert horizontal rule |
| 8 | Insert table, Insert column or row, Delete column, row, or table |
| 9 | Undo typing, Repeat typing |
| end | Cancel (editing only) |

- **Popups**:
  - Rich style: Heading 1/2/3, Paragraph.
  - Font size: Large/Medium/Small.
  - Font color: "Automatic" + palette.
  - Highlight: "No highlight" + palette.
- **Overflow**:
  - Overflowing items go into "More options" (`newMessageCommands-more-options`), taken **from the end** first. A divider left at the cut is dropped (751803).
  - Fit is measured by the Fluent toolbar; there are no fixed widths.
  - Container-query CSS sets the slot column gap to `calc(100% − 28rem)` (≥240px), `− 38.5rem` (≥480px) and `− 49rem` (≥640px; threaded channel `− 52.7rem`). The bar has max-width 940px.

## 17. "+" Actions and apps, Attach, fun picker
- **"+" flyout** (930874; native apps first in list view, `simplifiedComposeViewType` live "list"):

| item | shown when |
|---|---|
| Collaborate with Loop | removed when strategic apps are on (live) |
| Attach file | removed when Attach is in the toolbar (live) |
| Schedule message | `scheduleMessageEntrypoint` = "appAndContext" (live) |
| Set delivery options | always |
| Record audio clip | video disabled and audio enabled |
| Record video clip | `enableVideoMessaging` |
| Schedule meeting | not a channel post compose |
| Meet Now | channel reply and `allowMeetNowPolicy` |
| Edit in Markdown / Edit in rich text | `enableMarkdownUiInCompose` (live false) |
| Change permissions | new channel post |
| Post in other channels | `enableCrossPost` (live true), new channel post, not scheduled |

  Then installed apps, then suggestions (sort "Recent"/"A-Z"). Layout
  breakpoints: Small <480px, Medium <720px wide.
- **Attach menu** (916609):
  - "Search cloud files" box, then a "Recent cloud files" list.
  - Items: "Attach cloud files", "Browse Teams and Channels" (channels), "Upload from this device", "Upload from your mobile device" (conditional).
  - Disabled offline.
- **Fun picker** (505584):
  - Popover above the button, aligned to its end.
  - Tabs All | Emoji | GIFs | Stickers, each only when its policy allows.
  - Search "Find something fun", label "GIFs powered by GIPHY".
  - GIF categories: Trending, Reactions, Greetings, Perfect, Welcome, Congratulations, Thank you, Excited.

## 18. Delivery options, schedule send, Enter, limits
- **Delivery options** (648927, 871091):

| option | description | rule |
|---|---|---|
| Standard | "Message will be sent as usual" | — |
| Important | "Message will be marked as important" | Ctrl+Shift+I. The compose shows "Important!" |
| Urgent | "Recipients notified every 2 min for 20 min" | **disabled above 20 members**, with "Unavailable in chats with more than 20 people". Not offered in channels, meetings (unless flagged), plain-text or bot 1:1 chats |

  Choosing an option clears any scheduled send time.
- **Schedule send**:
  - Opened by **right-clicking Send**, from "+" › Schedule message, or from the scheduled-time label.
  - Popover "Schedule send" / "Send this message on": date picker up to today + `scheduleMessageDayLimit` (live 120), 30-minute time slots, "Continue", "Cancel scheduled time".
  - Unavailable before the first message in a chat ("You'll be able to schedule messages after you send your first message.") and for cross-posts.
- **Enter** (332416 `$e`):
  - **Ctrl+Enter always sends.**
  - **Plain Enter sends only when the Enter setting is "Default" and the formatting bar is collapsed**; otherwise it inserts a new line. Shift+Enter is always a new line.
  - The setting is user preference `composeUserSettings.enterKeyBehavior` = `Default` | `CreateNewLine` ("When writing a message, press Enter to: Send the message / Start a new line (to send, select Send or use {{hotkey}}).").
- **Hint under the compose** when it isn't empty: "**Shift+Enter** starts a new line."
  (or "**Enter** starts a new line." when the bar is expanded or the setting is
  CreateNewLine). The first word links to Settings. The hint is not shown for
  a new channel post.
- **Placeholders**, first match wins:
  1. Copilot chat
  2. "Reply in thread" (and the "…and channel"/"…and chat" variants)
  3. "Type a message" (bot)
  4. "Type a new message or / to see a list of commands" (behind a flag)
  5. "Type a message to this group." / "Type a message to {{name}}." (private chats)
  6. otherwise "**Type a message**"
- **Channel compose**:
  - Thread reply: a collapsed "Reply" (threaded: "Reply in thread").
  - New post: subject "Add a subject" (250 chars; Ctrl+Enter in it sends), announcement headline "Type a headline" + "Add a background image" + "Color scheme".
  - Footer: [fun picker, Attach, Copilot, Loop, +] … ["Also notify via email"] **Post**.
  - A draft shows "Continue your draft".
- **Pre-send checks, in order** (198077):
  1. empty → "Please type a message to continue."
  2. Loop still syncing
  3. video still uploading
  4. inline image
  5. Loop permissions
  6. group of ≥2 people
  7. recipients
  8. **too large → "Message is too large to send."** (`maxMessageContentSize` live 90112 bytes of UTF-8 HTML)
  9. announcement headline
  10. scheduled time in the past
  11. group name rules
  12. roster size
- **Editor and paste limits**: editor content 3072000; paste 1536000; plain-text paste 40000; table paste 200000 bytes; long link text 100.
- **Drafts**: `SaveMessageDraft` (sync debounce 400 ms, `composeDebounceDraftSyncDuration`),
  `SetConversationHasDraft`, `RemoveMessageDraft`, `DeleteRoamedDraft`. REST
  `POST/PUT/DELETE v1/users/ME/drafts`. "Discard" asks for confirmation (619123).
- **Send**: `ComponentsChatUtilsSendMessageMutation` → `POST {chatsvc}/v1/users/ME/conversations/{conv[;messageid=replyChainId]}/messages`.
  **Edit**: `PUT …/messages/{id}`.

## 19. @mentions (930187)
- Search is debounced 200 ms (max wait 1000 ms) via `SearchMentionsV3`
  (users, tags, channels/teams, apps). Chats over 1000 members use
  `largeRosterChatMentions`.
- **Everyone** ("Everyone — Notify everyone in the chat"):
  - group chats: only when `enableAtMentionEveryoneInGroupChat` and (members − 1) ≤ 250;
  - meetings: ≤ 1000 members;
  - otherwise disabled with "Not available for chats over 1,000 users."
  - More than 50 people adds the banner "# people will be notified".
- **Channels**:
  - Team and channel results are labelled "Team" / "Channel"; "@Channel — Notify everyone who's joined the channel".
  - Tags show as "Channel tag | # people" / "Team tag | # people".
  - At most 20 channel results.
- **Extra rows**: "Add someone to the chat" (group chats), "Share someone's contact info". Name suffixes "(You)" and "(External)".

## 20. Keyboard shortcuts (504800, Windows class `P`; per-flag, all live on unless noted)
| key | command | key | command |
|---|---|---|---|
| E | Edit focused message | Ctrl+Enter | send (compose) / focus message content (list) |
| Del | Delete focused message | Shift+Enter | new line |
| P | Pin | Ctrl+Shift+X | expand/collapse formatting |
| S | Save | Alt+Shift+O | attach file |
| U | Mark as unread | Ctrl+K | insert link |
| F | Forward | Ctrl+B / I / U | bold / italic / underline |
| T | Open thread | Ctrl+Alt+X | strikethrough |
| R | Focus reactions bar | Ctrl+Shift+C / Ctrl+Shift+B | inline code / code block |
| Q | Reply with quote | Ctrl+Alt+4 | quote |
| Alt+Shift+R | Reply to message | Ctrl+Alt+1/2/3, Ctrl+Alt+P | Heading 1/2/3, Paragraph |
| Ctrl+Alt+R | React to last message | Ctrl+Shift+I | mark Important |
| Shift+Up/Down | multiselect previous/next | Ctrl+Up | edit last message (`enableEditLastMessageShortcut`, unset) |
| Alt+T | thread list pane | Ctrl+Shift+7/8 | numbered/bulleted list (`enableComposeListShortcuts`, unset) |
| Ctrl+J | next unread thread | Alt+A | Copilot in compose |
| Shift+Esc | mark all as read | Alt+Shift+E | audio/video recorder |
| Ctrl+O | pop out conversation | Ctrl+Alt+= / Ctrl+Alt+- | insert / delete table row or column |

Menu items show the shortcut text; hover-bar buttons expose it through `aria-keyshortcuts` instead.

## 21. Services (chat service `{chatsvc}/v1/users/ME/conversations` unless noted; worker `inner_services_i`)
| action | GraphQL (client) | REST |
|---|---|---|
| send | `sendMessage` | `POST …/{conv}/messages` |
| edit | — | `PUT …/{conv}/messages/{id}` |
| delete / undo | `deleteMessage` / `undeleteMessage` | `DELETE …/messages/{id}?behavior=softDelete` / `DELETE …/messages/{id}/properties?name=deletetime` |
| react | `updateMessageEmotion` | `PUT`/`DELETE …/messages/{id}/properties?name=emotions` |
| who reacted | `messageAnnotations` | `GET v1/threads/{conv}/messages/{id}/annotations?filter=Type&value={key}` |
| save | `setReplyChainSaveState` | `PUT …/{conv}/rcmetadata/{rcId}` with body `{s, mid}` |
| mark unread | `markMessageAsUnread` | consumption horizon (`…/{conv}/properties?name=consumptionhorizon`) |
| forward | — | `POST …/{target}/messages/forward` |
| pin | `setPinnedItemsThreadProperty`, `chatPinUnpinPinbarMessage` | thread property |
| typing | `sendTypingIndicator` | `POST …/{conv}/messages` (`Control/Typing`) |
| read receipts | — | `GET v1/threads/{id}/consumptionhorizons` |
| drafts | `SaveMessageDraft`, `RemoveMessageDraft` | `v1/users/ME/drafts` |
| translate | translate mutation | middle tier `POST chats/{id}/messages/languages/{lang}` |

## → TODO
- Check every number in §3, §11 and §15–16 against the live DOM once a chat
  with messages and a compose box is open on winpc. Nothing was mounted during
  this read.
- Pill and hover-toolbar emoji pixel sizes and colours (Griffel hashes in
  226455/348213 not resolved).
- Meeting started/ended cards and the meeting-object chiclet (318259
  meeting-object code), and the announcement card layout (598599).
- Fluent icon names for control rows (698714 re-exports).
- The schedule-send default time (332491 `w()` returns the next 08:00;
  not confirmed as the default).
- The discard-draft dialog strings (619123) and the final @mention result ordering.

## OST status against this spec
- [ ] Message grouping: 5 minutes between consecutive messages; breaks on sender, control message, call recording, shared message, a message with replies (chat), and any date or "Last read" divider.
- [ ] Name only on the first message of a group and never on own messages; avatar only on the first message from others; persistent timestamp on the name line.
- [ ] Bubble colours, corner squaring by top/center/bottom position, 12px/2px gaps, and max widths per the §3 container breakpoints.
- [ ] Timestamp formats (Today hidden, Yesterday, weekday under 7 days, d/m, d/m/yy) and their tooltips.
- [ ] Date divider only on day change (none at the top in comfy); bold brand "Last read" divider; Jump to last read / New messages buttons.
- [ ] Edited label with "Edited {{editTime}}" tooltip; deleted tombstone with Undo; Sending/Failed states with Retry/Edit/Delete; IMPORTANT/URGENT labels.
- [ ] Read receipt icon only on the newest sent and newest seen own message; seen rule from consumption horizons; only for 2–20 members.
- [ ] Typing indicator text forms, 22 s timeout, sending throttled to once per 20 s, hidden above 20 members and in channels.
- [ ] Every control-message template in §9, including the bold call duration and the missed-call rule.
- [ ] Channel post: subject, "Open N replies from …" summary (no singular), collapsed "Reply" compose, "Post in channel".
- [ ] Hover bar: 4 default reactions (from user preference), More reactions, divider, contextual Edit / Reply with quote / Reply in thread, More options.
- [ ] Right-click menu with the reaction strip, keeping the hover-bar actions; native menu when text is selected.
- [ ] ··· menu in registry order; hover-bar actions removed; first 3 secondary items by usage; Translation submenu in chats; Report this message; More actions submenu.
- [ ] Edit and Delete with no time limit; Delete with no confirmation plus Undo; Edit hidden for Urgent messages.
- [ ] Pin/Unpin "for everyone", Save/Unsave, Mark as unread, Copy link (text vs title), Forward (image limit, multiselect split), Share to Outlook, Immersive Reader, Read by N of M.
- [ ] Reactions: pills ordered with own first, toggling, a 20-per-user limit, "+N" overflow counted in people, who-reacted hover list, add-reaction button.
- [ ] Reaction REST calls (`properties?name=emotions` PUT/DELETE) and the annotations fetch.
- [ ] Simplified compose: single-line side toolbar vs multiline bottom toolbar; button order Format, Emoji/GIF/Stickers, Attach, Loop, +, Send.
- [ ] Formatting bar groups and order; overflow taken from the end into "More options".
- [ ] "+" flyout items; Attach menu; fun picker tabs.
- [ ] Delivery options (Urgent disabled above 20 members), schedule send on right-click of Send, Enter behaviour and setting, hint text.
- [ ] Pre-send checks, 90112-byte message limit and its error text, draft save, debounced at 400 ms.
- [ ] @mention rules (Everyone limits, channel and team mentions, tags).
- [ ] Message and compose keyboard shortcuts in §20.
