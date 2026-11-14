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
| failed actions | Retry and Delete (`message-failed-retry`, `message-failed-delete`). Edit (`edit-restricted-message-button`) appears only for a pasted image blocked by policy. See docs/spec/send-pipeline.md §5 | 317519 |
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
  - It lives in the chat-pane gutter box (`data-tid="chat-pane-gutter-box"`) above the compose box.
  - **Avatar**: the typer's avatar (`avatarUrl` from the `typingUsers` query, which is their photo) sits 16 px into the compose box and 24 px above it. The compose box covers its bottom 8 px.
  - **Label** (`typingUsersLabel`): size small (12 px), one line with an ellipsis, margin `0 0 4px 12px`.
    - In a **1:1** chat the label is screen-reader-only (`avatarOnlyTypingIndicator` = one-on-one, `isGroup: !oneOnOne`), so the indicator is the avatar plus dots.
    - In a group chat the label shows between the avatar and the dots.
  - **Dots**: 6 px dots on a 9 px pitch, starting about 6 px after the label (or after the avatar in a 1:1). They sit roughly on the avatar's centre line.
  - All of this was measured in Teams web (same client) for "OST Test 1 is typing" in a 2-person group chat on 2026-11-06.
  - The typer's name comes from their MRI (`from`). Group-chat typing events carry no `imdisplayname`.
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

### Verified on the live client (winpc, OST group test, 2026-11-06)
- **Rows**: a control row is 28 px tall and a call row 36 px. Both are flush with the rows around them (no top padding).
- **Icon**: 20×20 at row x 6, y 8, in NeutralForeground3 (#616161).
- **Text**: 12/20 #616161 at x 40, y 10.
- **Names**: regular weight (clickable personas), *not* bold. The spec above says "bold persona"; the live client shows weight 400.
- **Call row**: the time, then an EM space (12 px), "Call ended", a no-break space, and the duration at weight **700**.
- **Icons**, from table `ir` in module 349533, resolved to Fluent names:

  | type | icon | type | icon | type | icon |
  |---|---|---|---|---|---|
  | AddMember | PersonAdd | DeleteMember | PersonArrowLeft | TopicUpdate | Edit |
  | ModalityUpdate | Edit | PictureUpdate | PersonCircle | ThreadShared | PersonAdd |
  | Call | Call | CallMissed | CallMissed | Meeting | Video |
  | ScreenShare | ShareScreenStart | MemberJoined | CalendarAdd | MemberLeft | PersonArrowLeft |
  | MemberRenamed | PersonEdit | RetentionDeleted | Chat | EscalationUpdate | AlertUrgent |
  | MeetingPolicyUpdated | ErrorCircle | ShowHiddenChatHistory | Eye | Recording | Record |
  | StopRecording | RecordStop | TrashCan | Delete | PinMessage | Pin |
  | UnpinMessage | PinOff | ConsentInvites | PersonAdd | ReplyChainCreated | ChatMultiple |
  | UploadedRecording | CloudArrowUp | Transcript | SlideTextEdit | MeetingScheduled | Calendar |
  | MessageMoveCompleted | ChatCursor | CreateThread | Channel | AddCustomApp, DeleteCustomApp | Apps |
  | GroupCopilot | Sparkle | | | | |

  Each icon is a CompoundIcon: regular normally, filled on hover. Its appearance is the default, brand or red class.
- **AddMember parsing** (75579 `ma`):
  - The targets are the `<target>`s minus the initiator; bot ids are skipped.
  - If no target is left, it is a self-join ("joined the conversation").
  - Each `<detailedtargetinfo>` gives `<id>` and an optional `<friendlyName>`.
  - `<sharehistorytime>` gives days = round((eventtime − sharehistorytime) / 86400000).
- **Missed call** (75579 `rs`): ended, not a meeting, fewer than 2 participants, and not the third flag.
- **"Call started" events produce no row.**

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
  Measured 2026-11-09 in a Posts channel, Teams desktop draws them anyway. The
  `announcement-header-box` is the card's width less 36 (680 at a 716 card),
  64 down, 244 tall, radius 4, in its colour scheme. The headline is 32/40
  semibold, centred, in the scheme's text colour. The subject `h2` follows
  12 under it, then the body.
- **Wire** (captured from Teams, OST TEST 74/75): a new post carries
  `properties.subject`, `properties.title` ("" unless it's an announcement),
  `properties.policyViolation: null`, and top-level `postType` ("Standard" or
  "Announcement") and `crossPostChannels: []`.
  - An announcement's `properties.cards` is
    `[{appId:"announcement-card", cardClientId:"announcement-card-<32 hex>",
    contentType:"application/vnd.microsoft.teams.messaging-announcementBanner",
    content:{colorTheme:"0".."11"}}]`.
  - A picture banner adds `content.imageData {origImage{src},
    croppedImage{src, imageWidth, imageHeight, imageAltText},
    isTeamsIllustration, colorTheme}`.
- **Colour schemes** (module 8196): "0".."5" use the Blue, Lavender, Pink,
  DarkOrange, Gold and Forest palettes' Background2 with Foreground2 text;
  "6".."11" use the same palettes the other way round. Light theme:
  #A9D3F2/#004377, #D2CCF8/#3F3682, #F7C0E3/#80215D, #F4BFAB/#7A2101,
  #ECDFA5/#6C5700, #BDD99B/#294903; the dark theme swaps the two tokens.
  Names (light / dark): Periwinkle Blue / Aegean blue, Lavender / Midnight
  purple, Rose / Sangria, Orange sherbet / Espresso, Flax yellow / Gothic
  gold, Teal / Space green, Navy blue / Cornflower blue, Indigo / Thistle
  purple, Mulberry red / Pink, Fire orange / Coral, Raw umber / Mellow
  yellow, Ocean green / Jade.
- **Post composer** (Post in channel; measured 2026-11-09). It is a card
  like the post cards: radius 6, a #E0E0E0 line, shadow 0 0 2 / 0 4 8, and
  27.7 above the bottom. Post in channel hides while it is open.
  - **Author row** (56.7 tall, 16.7 in): avatar 32, name 14/20 semibold,
    and **Close** (empty) or **Discard** (the delete icon; asks "Discard
    draft" when there's text).
  - **Add a subject**: 18 px with a #707070 placeholder, padding 15 0 16,
    10.7 in. Its underline is 0.67 #616161, or 2 px brand when focused. It
    takes 250 characters and has the focus when the composer opens.
  - **Formatting bar**, always open. Announcement (megaphone) comes after
    Code block, and there's no Discard.
  - **Editor**: at least 104 tall.
  - **Tools**, 16 under the editor from 8.7: Emoji, GIFs and Stickers;
    Attach files; Loop components; Actions and apps; ···.
  - **Post**: brand, 96 × 31.3, 16.7 from the right.
  - **Announcement** inserts a banner 12.7 in and 69.3 down (244 tall,
    radius 4) in Periwinkle Blue. Its headline is "Type a headline" (40/52
    semibold, centred, 44 characters). Color scheme (a 16 px swatch) and
    Upload an image sit in a white group 12.8 from the banner's bottom
    right. The scheme picker shows 12 swatches (16, radius 4, 28 apart, two
    rows) above the button. The subject becomes "Add a subheading", 12
    under the banner.
  - **Upload an image** opens "Add a background image": 918 wide, padding
    27 32 32, radius 8, a 18/25.7 bold title, and Close.
    - Empty: a 854 × 360 dashed #D1D1D1 drop area with "To get the best
      result, choose an image that's at least 848x244 px." and an outline
      Upload an image button; the hint again (info 12) and Cancel.
    - With a picture: react-easy-crop across the dialog (344.3 tall,
      contained), a 848 × 244 frame (2 px white, 50 % white shade), drag
      and wheel, a 320-wide zoom slider (1 to 4, step 0.05), Cancel and
      Done.
    - After Done the composer's banner is 200 tall with the crop, a white
      headline, and **Delete background image** (32 × 33.3, 80 % white,
      radius 6, 12.7 from the top right).
    - Post uploads the crop to AMS (`pish/image`, view `imgpsh_fullsize`),
      lists it in `amsreferences`, and sends `imageData` with the crop as
      both `origImage` and `croppedImage` (`src`, `imageWidth`,
      `imageHeight`, `imageAltText` "", `id`) and `appName:
      "AnnouncementBanner"`.
    - Teams draws a picture banner 16 in and 64 down, the card's width
      less 32, at a fixed 684 × 190.08 ratio (cropped to fill), with a
      white headline and the body 16 under it.

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

### Measured in the client (winpc, 2026-11-07; CSS px with the DPR 1.5 factored out)
**Hover bar** (`message-actions-container`)
- 245 × 32 for 4 reactions plus one action; white, radius 4, Fluent shadow16 (a drop-shadow on the PopoverSurface).
- It sits **end-aligned on the bubble's top edge**: its right edge is the bubble's right edge, and its bottom is the bubble's top.
- Contents, left to right:
  - 7 px in, the reactions: 32 × 31 buttons, each with a 20 px emoticon at (6, 6). On hover the emoticon scales to 1.2 (24 px) and the button gets no background.
  - More reactions (EmojiAdd20).
  - A vertical Fluent Divider: 8 wide, padding 0 4, with a 1 px NeutralStroke2 line 21 px tall at y 5.
  - The action (Edit20 on yours, the quote glyph on others').
  - More (MoreHorizontal20, 32 × 32).
  - 6 px of padding at the end.
- Icons are Fluent transparent buttons: #424242 at rest; on hover the filled glyph in brand.

**Emoticons** are Teams' images, not system emoji:
- Image: `{statics}/evergreen-assets/personal-expressions/v2/assets/emoticons/{id}/default/{size}[_anim]_f[_s{tone+1}].png?v={etag}`.
- Metadata: `/evergreen-assets/personal-expressions/v1/metadata/{emoticonAssetVersion}/{locale}.json`, live version `ec4576179210cde40ce5494513213583`. It holds the categories, with `id`, `description`, `shortcuts`, `unicode`, `etag`, `diverse` and `keywords` for each emoticon.
- Sizes (401251 `b`): extra-small 16/20, small 20/50, medium 30/60, medium-large 40/100, large 50/100 and extra-large 100, normal/hi-DPI.
- The hover bar's reactions are medium and the reaction pills are small.
- The server key `like` is drawn with the `yes` asset.

**Reaction summary**
- Pills are 34 × 26 and fully round, 2 px apart.
- The row overlaps the bubble's bottom edge by 4 px. It sits 15.7 in from the bubble's start on others' messages, and at the bubble's **end** on your own.
- A pill holds a 20 px emoticon at (7, 3); its count shows only when it is over 1.
- Your pill has a brand border; others have NeutralStroke2.
- The add-reaction button (34 × 26) has a 1 px NeutralStroke2 border and EmojiAdd16 at (9, 5).

**Who reacted** (`diverse-reaction-user-list-popover`, hovering a Fire pill reacted by one person)
- A Fluent MenuPopover centred under the pill, its top 4.3 below the pill's bottom.
  - 198 wide for a short name; min-width 138, and rows have max-width 290.
  - White, radius 4, shadow8, padding 4 / 0 / 8; 85.3 tall for one row.
- Header: the reaction's name ("Fire"), 12 px weight 300, NeutralForeground3, padding 8 / 16 (32 tall, at y 4.7).
- The list (`diverse-reaction-user-list`, role menu): at y 36.7, padding 4, min-height 32, max-height 236, scrolling; items 2 apart.
- A row (`diverse-reaction-user-list-item`, aria "Chat with {name}"):
  - 32 tall, radius 4, padding 6 / 6 / 6 / 12;
  - the 20 px round avatar at (12, 6);
  - the name at 38 (a 2 px padded span), 14 px, weight 400, NeutralForeground2, clipped.

**Reaction picker** (`reaction-picker-root`, 317 × 372)
- Search: 242 × 32 at (16, 16), NeutralBackground3, radius 4. The placeholder is "Find something fun"; the aria label is "Search for emoji, GIFs or stickers".
- Customize default reactions: 32 × 32 at (270, 16).
- One scrolling list runs from 56 to 320:
  - A heading (14/20, weight 500) 10 px down for the first section and 2 px for the rest.
  - The grid 22 px under the heading: 290 wide, with 15 px top and 20 px bottom padding, of 46 × 46 buttons, six a row. Each holds a 30 px emoticon at (8, 8).
  - Emoticons with skin tones carry a 5 × 5 #B9B9B9 dot at (40.3, 0.6).
- A divider at y 320, then the tabs: 27.3 × 43.3 each, from x 8.7.
  - The selected tab is #EBEBEB.
  - Each tab icon is the top half of `/evergreen-assets/personal-expressions/v2/assets/categories/{categoryId}/thumbnail.svg` (a 20 × 40 single-colour sprite) at (3.6, 11.7): brand when selected, NeutralForeground3 otherwise.
- **Recent** is the user property `recentReactions`: a JSON string of ids, newest first, capped at 36. Reacting moves the id to the front, and Teams writes the property back.
- Without that property, Recent is `recentReactions.defaultReactions` (live: surprised, cry, angry, hearteyes, cool, handsinair, fistbump, fire, … rock).
- **Quick reactions** are the user property `defaultMessageReactions`; without it, like, heart, laugh and surprised.

**Channel posts and replies** (OST Test Team › General, a classic channel)
- Card (`channel-pane-message`): 716 wide, white, radius 4, shadow 0 0 2 rgba(0,0,0,.12) + 0 1 2 rgba(0,0,0,.14), no border.
  - The post: a 32 px avatar at (18, 16) with a 10 px presence badge at (40, 38). The name (14 px) is at (60, 21.8), with the time (12 px #616161) 10 after it.
  - The text is at (18, 64), 680 wide. The reaction summary (`channel-message-reaction-summary`) sits 17 under the text; the add button always shows.
  - Replies (`response-surface`): a 0.67 px #F0F0F0 line on top, 8.7 padding. Each reply has a 20 px avatar at 18 with a 6 px badge at (14, 14), the name and time (12 px, 8 apart) at 50, and the text 20 down (646 wide). Replies are 56 apart.
  - "Reply in thread" (`quick-reply-placeholder-reply`, 14 px semibold #616161) sits in a 48 px row under a #F0F0F0 line, with your 20 px avatar at 18.
- Hover bar (`channel-message-action-menu`, 241.3 × 32): Like, Heart, Laugh, Surprised, More reactions | Edit (yours), More options.
  - On a post it sits inside the card, 10 from the end and 11 down.
  - On a reply it sits at the card's end, its bottom 3.7 above the reply.
- ··· on a post: Forward, Follow thread / Unfollow thread ("New" badge), Copy link, Save this message, Delete, Pin for everyone, Open conversation in new window | Mark as unread, Share to Outlook, Translate | More actions. 260 wide.
- **Open conversation in new window** (measured on winpc, 2026-11-09):
  - A child window, 588 x 493, titled "<team> | <channel>", with the child-window title row.
  - Header (61, #FAFAFA, a #E0E0E0 line under it, padding 0 7 0 20):
    - the team's picture (32, radius 2) at 20;
    - the channel (14/20 semibold) at 62, 9.7 down, and "Post by {author}" (12/16 #616161) at 31.7;
    - at the right, a 1 px #F0F0F0 line from 18 down, then More channel options (32 x 31.3): Find in post (Ctrl+F) | Follow / Unfollow thread;
    - while finding, Find in post's toggle (32, brand) comes before it, and the find pane fills the window.
  - The thread on #FAFAFA (runway padding 7 16 3), as one 526-wide card (radius 8, shadow 4):
    - the post: the avatar 32 at (18, 16), the name (14/20) at 60, 13.4 down, the time (12/17.14 #616161) under it at 33.4 then "Edited" 8 after, the text at (18, 64), the reaction summary 17 under it;
    - a 0.67 px #F0F0F0 line;
    - each reply in a 70.3 block: the avatar 20 at (18, 8), the name (12/17.14) at 50, 8 down, the time under it at 25.1, the text at (50, 42.2), 8 below;
    - where the day changes, a 16 px timestamp-divider ("Today", 12/16 #424242, centred).
  - Hover bars: on the post, 10 from the card's end and 11 down. On a reply, flush with the card's end, 28 above the block (its bottom 4 into it).
  - "Reply in thread": Teams' compose (Format, Emoji, Attach, Loop, Actions and apps | Send), 28 in and 30 from the right, 26.7 above the bottom.
  - Messages come from the reply chain, `GET {chatsvc}/v1/users/ME/conversations/{channel};messageid={post}/messages` (the post first, then its replies). Replies go to the same conversation.
- **Follow thread** (seen on the wire while toggling it in Teams):
  - `PUT {chatsvc}/v1/users/{me}/conversations/{conv}/rcmetadata/{root}` with `{"f":1}` to follow, `{"f":3}` to unfollow;
  - then `PUT …/messages/{root}/properties?name=emotions` with `{"emotions":{"key":"follow","value":1|0}}`.
  - The menu shows "Unfollow thread" (ChatMultipleMinus20) when following and "Follow thread" (ChatMultiple20) otherwise.
  - A post you wrote shows "Unfollow thread" with neither record (auto-follow of authored threads).
- Emotion keys `acks`, `follow` and `star` are not reactions; the summary skips them (719107 `OS`).
- ··· on a reply: Forward, Copy link, Save this message, Delete | Share to Outlook, Translate, Immersive Reader | More actions. Content-sized (166.6).
- Edit in place uses the multiline compose (always, even for one plain line). It spans the card in the item's place, from the line above it; the hint sits under it, then 11.4 to the next reply.

**Reaction overflow and pressed state** (live, with seven reactions from the test account)
- Teams showed five pills plus `diverse-reaction-overflow-button` "+3" (aria "3 overflow reactions."). The button is 28 × 26 (padding 0 6, min-width 26) with a 0.67 px #E0E0E0 border and 12 px text.
- The overflow hover list is titled "More reactions" and is 198 wide.
  - Each row shows the reaction's emoji (20 px).
  - Our own rows end in a Dismiss16 remove button 6 from the row end, with the emoji 14.7 before it. Its aria is "Remove reaction".
  - Pill lists have no remove button.
- Pill borders are 1.33 px in brand when the reaction is ours.
- Hover-bar reactions we gave with exactly that id get a 14 × 2 #444791 underline (BrandForeground2), centred, 27 down; a toned Like does not press the plain one. More reactions is underlined when we reacted with something outside the quick reactions.
- Teams' estimate (`xe`): a single-count pill is 34; otherwise emoji × 20 + 4 + digits × 8 (× 1.0676 when ours) + 14. Room is five slots × 36 (three under 480 wide).
- Own pills sort by count, with ties going to the one we reacted to first; then the rest follow in arrival order.
- A pill shows its first three variants in arrival order. When there are more and ours is toned, the first untoned one gives way (`Ne`).

**Reaction keys** (77708, verified live)
- Teams works in emoticon (client) ids and maps three to the service's keys: client `yes` is the service's `like`; client `like` is `likeWithFaceMSER`; client `star` is `starMSER`. Every other id is the same on both sides.
- The summary groups by common key: the client id without a final `-tone{digit}` (at most 40 characters before it).
- A toned reaction is sent as `{id}-tone{n}`; a toned thumbs-up from Teams is `yes-tone2` on the wire (seen live).

**Skin tone** (user property `preferredSkinToneIndex`, a string "0"–"5": none, light, medium light, medium, medium dark, dark)
- With a tone set, emoticons with tones show in it in the picker, and the hover bar's Like becomes `yes-tone{n}`.
- Clicking a pill we have not reacted with adds the emoticon in our tone. Picking another tone of an emoticon we reacted with replaces our old one.
- Picker cells of reactions we gave read "Undo {name}". Toned cells read "{name} with {tone} skin tone", e.g. "Hands celebrating with no skin tone".
- Right-clicking a cell with tones opens the six tones: a 309.3 × 79.3 surface, padding 16, radius 4, 7.6 right of the cell and 65.4 above its top. It holds 46 px cells (`emoticon-button-{id}-tone{n}`).
- Saving a tone in OST was picked up live by the desktop client: its hover-bar Like became `yes/default/60_f_s3.png`.

**Customize default reactions** (`customize-reactions-trigger`, EmojiEdit20 at (269.7, 15.7) of the picker)
- `customize-reactions-dialog`: 600 × 392.7, radius 4. The title is "Customize your reactions & appearance in Teams" (20/28 semibold, at 24.7, 24.7). Under it, "Click on a reaction below, then choose an emoji to replace it with." (14/20, at y 61.3).
- Five slots (`customize-reaction-picker-entrypoint`), 46 × 46 with 15 px gaps, centred at y 116.7.
  - Each slot has a 1 px NeutralStroke1 border and radius 4, with the 30 px emoticon at 8. While its picker is open the slot is NeutralBackground1Hover with border #C7C7C7.
  - An empty slot is "Choose an emoji" with Add24.
  - Clicking a slot opens the reaction picker centred under it. That picker has no customize button, and its search is 256.7 wide.
  - Backspace or Delete removes a slot (the hint "Use backspace or delete to remove reaction" is read out).
- Below the slots, "Choose a skin tone. After selection, reactions and emoji will appear with this skin tone." (470 wide, at y 198.7). Under it, `skin-tone-radio-group` at y 258.7:
  - six 42 × 50 radios, 15 apart and centred, each a 30 px circle at 6;
  - the circles are radial gradients from 26.4 % to 100 %, centre (8.86, 22.5), radius 23.19: #FCD53F→#FFB02E, #F4BFAA→#B77C6C, #E8B192→#A0685B, #B28876→#794E54, #875D59→#4E2C32, #26131B→#503B3B;
  - the selected radio has a 30 × 4 brand bar with radius 2 at y 40.
  - Choosing a tone re-tones the slots that have tones.
- Cancel and Save are 96 × 31.3 at (375.3, 336.7) and (479.3, 336.7). Save is disabled (#F0F0F0 with #BDBDBD text) until something changes.
- Save writes `defaultMessageReactions`: a JSON string of service keys (live: `["yes-tone2","heart","laugh","surprised"]`; `yes` saves as `like`). It also writes `preferredSkinToneIndex` when the tone changed.

**Quoted reply** (verified by sending one from Teams and reading it back)
- **Preview text** (443282 `QuotedReplyContent`, constants 572771). The preview walks the quoted message's nodes:
  - text as it is;
  - an Emoji img as its `alt`, and a CustomEmoji as `:alt:`;
  - any other `img` or AMSImage (GIF, sticker, picture) as " 📷 ";
  - an AMSVideo as " 🎥 ";
  - `li` as "n." in an `ol` or "•" in a `ul`.

  Teams stops taking nodes once the text is longer than 200 characters. Verified on Teams web: quoting "OST TEST 58 before the GIF" + GIF + "and after it…" gave "OST TEST 58 before the GIF 📷 and after it …". OST sent a reply quoting a sticker with preview `📷`, and Teams web rendered it.
- Wire format: `<blockquote itemscope itemtype="http://schema.skype.com/Reply" itemid="{id}"><strong itemprop="mri" itemid="{mri}">{name}</strong><span itemprop="time" itemid="{id}"></span><p itemprop="preview">{text}</p></blockquote>` followed by the reply's `<p>`.
- The service puts one `\n` between the card and the reply. `properties.qtdMsgs` is the JSON-stringified references and is sent only when quoting; the service adds `validationResult`.
- Card, both in a bubble and in the compose box:
  - NeutralBackground2, a 1 px NeutralStroke3 border, radius 4, shadow2;
  - a 2 px #C7C7C7 bar 4 in;
  - from 18 in, the name and `M/D/YYYY h:mm A` in 12 px NeutralForeground3, 8 apart, then the text in 14/20;
  - 8 px at the end.
- In a bubble the card is at (15.7, 10.7), 52 tall, and the reply text sits 4 below it. Clicking it goes to the quoted message.
- In the compose box the card is 56 tall, at (12, 14) of the editor. The header row is 20 tall and ends with a 20 px "Remove Reference" button.

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

### Measured (winpc, 2026-11-07)
- **Chat compose, single-line**:
  - The box is 748 × 45.3 at 72 in on each side, white, with a 0.67 px #E0E0E0 border and radius 6. The footer keeps 2 + 16 px for the hint and 6 more under it.
  - The editor's padding is 10 16 8 12 (14/20, min-height 38). The placeholder is #616161.
  - The side toolbar has 32 px buttons, 6.7 down: Format, Emoji/GIFs/Stickers, Attach, Loop, Actions and apps. Then the send group (40.7 wide): a 24 px divider 4 in, then Send 8.7 in, ending 6.7 from the box's end.
  - Focused, a 2 px brand line runs along the bottom.
- **Formatting bar open**:
  - The box grows to 193.3: the bar is 43, the editor at least 104, then the 44.7 bottom toolbar.
  - Bar buttons start at (6.7, 9.7), in groups 8.6 apart with a divider. Buttons that don't fit go to "More options" (···). Discard (Delete20) sits at the end, 6.7 in.
- **In-place edit** (Edit on your message):
  - The compose replaces the bubble, its name line and its reactions. It is 172 in from the list's start and 72 from its end (648 wide in an 892 pane), 12 below the item's top.
  - Top part: border on all sides but the bottom, radius 6 6 0 0. The editor holds the quote card (with Remove Reference) at (13.3, 14.7), then the text.
  - Bottom toolbar (`simplified-compose-bottom-toolbar`, 44.7 tall, 0.67 px #E0E0E0 bottom border, radius 0 0 4 4):
    - buttons 6 down: Format, Emoji, Attach, Actions and apps;
    - then the send group: the divider at 4, Cancel (`newMessageCommands-discard-draft`, Dismiss20) at 8.7, Done (`newMessageCommands-send`, Checkmark20) at 40.7, ending 6.7 in.
  - Under it, right-aligned 17 in (12/16): the link "Shift+Enter" (BrandForeground1 #4F52B2, aria "Select Shift+Enter to open settings"), 4 px, then "starts a new line." (#242424).
  - **Escape does nothing while editing.** **Cancel always asks** with `messagedraft-discard-dialog`:
    - 600 × 156, radius 8; the title "Discard draft" (20/28 semibold) at 24.7 and Close;
    - "You can discard your draft or cancel to keep editing" at (22.7, 62);
    - Cancel and Discard (brand), 96 × 31.3, at y 100.
  - A Teams edit (seen live) keeps the quote's blockquote and `qtdMsgs` and sends the full property set. The service then stores `edittime` (ms) and `version` = `edittime`; `clientmessageid` and `composetime` are unchanged.

### "+" and delivery options (measured, winpc)
- "+" (`sendMessageCommands-message-extension-flyout-command`) opens a 341.3-wide surface:
  - the search box (`extensibility-app-picker-search-input`) at (14.7, 17.3), 310 × 30.7, "Search for apps";
  - `SECTION_firstPartyMessageExtensions`: Schedule message, Set delivery options, Schedule meeting, Record video clip. Rows are 36 tall with a 20 px icon 8 in and the label at 40, 14/20;
  - then a separator, `SECTION_recent` (installed apps, e.g. Clipchamp, Approvals, Power BI, Praise, Updates, Viva Learning, Workflows), "Add a new app" with store suggestions (90 px rows with Add buttons), and "Get more apps".
- Set delivery options opens a 317.3 × 161.3 listbox:
  - `standard-delivery-option` (Chat20Regular), `important-delivery-option` (Important20Regular, #C4314B), `urgent-delivery-option` (AlertUrgent20Regular, #C4314B, 4 further in);
  - rows are 48 tall; the title is 14/18.7 and the description 12/16, at 40.7;
  - the selected row is #F5F5F5 with Checkmark20 at 284.
- With Important chosen, the compose shows an "IMPORTANT!" row above the editor: 26 tall, 14/20, weight 700, uppercase, #DA3B01. The box grows to 71.3.

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

### Measured (winpc, 2026-11-07)
- **Bar.** `simplified-formatting-toolbar` is 43 tall. Buttons are 32 px from x 6, y 9. Groups are 8.7 apart with a divider. At 746.7 wide it shows Bold … Code block, then More options at 416 (no divider), with Discard at the end.
  - The width tiers (490 / 385 / 280) follow the conversation's width, not the box's. A 468 px box in a 532 px conversation (1280 with the threads pane open) shows B I U S | lists | Highlight, Font color, Font size | ···.
  - The bar is a flex row with `column-gap: calc(100% − 49rem)` (rem = 10 px; 38.5rem from 480 wide, 28rem from 240). So the buttons' toolbar is 490 − 32 = 458 wide from 640 up (measured 458 at 746.7); items that don't fit, with More options, go to the menu.
  - Every button's icon was copied from Teams' DOM into `fmt-*.svg` (Teams draws Fluent 20 px icons in a "2 2 16 16" viewBox).
- **More options menu.** 247 wide, max 306 tall (it scrolls), padding 8/0, radius 4, shadow 16.
  - Rows are 32 tall with a 16 px icon at 15.7 and the label at 41.7. Rich style is 34.3 tall with a 20 px icon and its label at 45.7.
  - Dividers are 16.7. Rich style shows the current style ("Paragraph") and opens its menu beside it.
  - Labels: "Code (Ctrl+Shift+C)", "Clear all formatting", "Decrease indent", "Increase indent", "Insert horizontal rule", "Insert table", "Insert column or row", "Delete column, row, or table", "Undo typing", "Repeat typing".
- **Highlight and Font color.** A 125.3 × 101.7 popover centred over the button, its bottom at the button.
  - "No highlight" / "Automatic": 100 × 24.3 at (12.7, 8.7), with a #D1D1D1 hairline.
  - Eight 16 px swatches, 28 apart, from (12.7, 45), radius 4, border rgba(37,36,36,.2).
  - Highlight colours: Kobi red #DF9299, Rose bud #F4A593, Goldenrod #FDD472, Primrose #E5F18F, Mantis #82CDA8, Regent St. blue #9DD9DB, Periwinkle gray #C7D4E8, Pale rose #EBD3E1.
  - Font colours: Red #B6424C, Tuscan orange #CD5937, Sunglow #FDC030, Pear #BDCB4C, Eucalyptus #2B9B62, Faded jade #37797B, Fun blue #1E53A3, Tyrian purple #A5397A.
- **Font size** (`compose-font-size`). 104.8 × 113.3, padding 8/4. Large / Medium / Small rows are 91.5 × 28, 32 apart, label at 12. Large sends `font-size:x-large`, Small `small`; Medium removes the size.
- **Rich style.** 130.4 × 150.3. Heading 1 is 18/300 (row 33), Heading 2 14/700, Heading 3 12/700, Paragraph 14/400 (rows 28), all #424242. They send `<h1>`–`<h3>`.
- **Insert link.** A 303.3 × 262.7 popover over the button: "Insert link", "Text to display" and "Address" inputs (270 × 32, #F5F5F5, radius 4, placeholders "Text to display" / "Link to an existing file or web page"), then Cancel and Insert (96 × 31.3) at 208.7. Insert is disabled until there is an address.
  - Links go out as `<a href rel="noreferrer noopener" target="_blank" title>`.
- **Code block.** An embedded editor with a "Plain Text ⌄" language menu (Teams' 44 languages), line numbers and a ··· menu. It sends the CodeBlockEditor paragraph plus `<pre class="language-…" itemid>`.
  - Header (measured 2026-11-10): the icon, language and chevron in #424242, and More options (32 × 31.3, 3.7 px from the right).
  - The menu is 195 px wide:
    - "Make this collaborative" (converts the block to a Loop component), then a divider;
    - a "Display option" header (#616161);
    - the "Auto-detect language" check item, on for new blocks.
  - With auto-detect on, the block takes the language its words point to as you type (highlight.js `highlightAuto`): a few lines of Rust become Rust, while "let x = 1; // hi" stays Plain Text. Picking a language turns auto-detect off.
  - Syntax colours exist only in the compose box; sent messages show plain code. highlight.js classes fold into five colours:

    | Colour | Classes |
    |---|---|
    | #237B4B | strings and numbers |
    | #4F52B2 | keywords, types, meta, tag names |
    | #C4314B | function and class titles, built-ins, attributes, and calls in Rust/JS/TS/C++ |
    | #707070 | comments |
    | #242424 | everything else |

  - The received card has the header (language and Copy), line numbers, and a horizontal scrollbar for long lines.
- **Headings and inline code as received** ("OST TEST 70"):
  - h1 is 18/300 on a 25.7 line, h2 14/700 on 20, h3 12/700 on 17.1, each with margin 3/0;
  - `code` is Cascadia Mono 14, white, 0.67 #D1D1D1, radius 4, padding 4, margin 0/2.
- **OST.** `RichText` (src/richtext.cpp) edits the compose box's QTextDocument and exports clean HTML, which `teams_html_with_media` turns into Teams' HTML.
  - Quotes and code blocks are marked paragraphs. QML draws the quote box and code card behind them, because QQuickTextEdit crashes on frames added while it shows the document.
  - "OST TEST 69", sent from OST with every format, matched Teams' wire format, and Teams web drew it exactly as its own messages.
- **Tables** (measured on winpc 2026-11-12, "OST TEST 111"; OST sent "OST TEST 112"):
  - **Insert table** (More options) opens a grid under its row, 15.33 in: 201.33 wide, white, radius 4, shadow 16, padding 16. "Insert {columns}x{rows} table" (14 px #242424) at 31.67, 16.67, then 7 x 5 cells of 24 px from 16.67, 36.67 (it doesn't grow). Cells up to the pointer are #5B5FC7 with a white 0.67 line, the rest white with #424242. Teams also has an "Allow edits" checkbox under the grid (a Loop table; not in OST until Loop components, AC4).
  - The table takes the box's full width with columns sized by their text: collapsed 0.67 #616161 borders, cells padded 0 5, rows 20.67. The cursor goes into the first cell, and the hint under the box reads "Enter starts a new line." Enter makes a new line in the cell; Tab goes to the next cell (from the last it adds a row), Shift+Tab back.
  - **Insert column or row ▸**: Insert column to the right, Insert column to the left, Insert row above, Insert row below. **Delete column, row, or table ▸**: Delete column, Delete row, Delete table. Both are Fluent menus (32 px rows 2 apart, padding 4, no icons; 174 and 106 wide), centred on their row, 9 above it.
  - Sent as `<p>&nbsp;</p><table><tbody><tr><td><p>…</p></td>…</tr></tbody></table><p>&nbsp;</p>` with no attributes (the service adds CRLF between the tags).
  - Received: auto width, collapsed 0.67 #D1D1D1 borders, cells padded 0 5, 14/20, centred vertically. OST draws borders at least one device pixel wide, as a browser does.
- **Not done yet.** The code card's "Make this collaborative" and the table grid's "Allow edits" (both need Loop), and the inline-code hairline box when receiving (Qt rich text can't draw one).

- **Schedule message** (measured on winpc 2026-11-10, "OST TEST 90"–"92"):
  - Where it's offered: "+" ▸ Schedule message (SendClock icon), first in the list, in chats and channels. It isn't offered in your own chat.
  - The popover:
    - 245.3 px wide, radius 4, shadow16, padding 16 / 12; it opens above the "+", its end 8 px past it.
    - "Send this message on" (14 px, #616161).
    - The date: filled #F5F5F5, "Tuesday, November 10", a calendar icon.
    - The time: filled, 48 half-hour slots; earlier slots are greyed for today.
    - Both fields are 220 px wide and 8 px apart; then Continue (brand, 31.3 px).
    - The default is the next 8:00 AM (seen as today 8:00 AM at 6:40 AM; the rule wasn't found in Teams' code).
  - The compose then shows "Select **Send** to deliver on {Tuesday, Nov 10} at {8:00 AM} ⌄".
    - It is 12 px brand in a 25 px row, 12 px in. Channel posts say **Post** instead of Send, and editing says **Done**.
    - The chevron reopens the popover with "Cancel scheduled time" under Continue.
  - Sending: `POST {chatsvc}/v1/users/ME/drafts` with:
    - `draftType: "ScheduledDraft"`, `draftDetails.sendAt` (epoch ms, as a string), and `innerThreadId` (the chat);
    - `message`: the usual message body plus `properties.draftId` (its clientmessageid), `draftDetails.sendAt` (ISO), `threadtype: "streamofdrafts"` and `innerThreadId`.
  - Listing: `GET {chatsvc}/v1/users/ME/drafts` returns `{"drafts": [...]}`, with each draft's type, chat and send time at its top level. The `48:drafts` stream can't be read as a conversation.
  - A scheduled message shows after the chat's messages:
    - a #FAFAFA bubble with a 0.67 px #D1D1D1 border, radius 6, and no time line;
    - "Sending on {day} at {time}" (12 px, #616161, 17.1 px line), with the text 21.1 px lower than usual;
    - a brand Clock 12 icon ("Scheduled");
    - hover: Edit and More, with no reactions; More holds Delete (Del) and Translation.
  - Delete cancels it: `DELETE {chatsvc}/v1/users/ME/drafts/{id}`.
  - Errors: "Failed to schedule.", "Failed to schedule. Message too large.", "This message was scheduled for a time in the past."
  - Edit ("OST TEST 93"/"94"): inline, with "Select **Done** to deliver on …" above the box (its chevron changes the time).
    - Saving sends `PUT {chatsvc}/v1/users/ME/drafts/{id}` with the same envelope. The message carries the draft's id as `id` and `properties.draftId`, plus `properties.edittime` (ms) and an ISO `version`.
    - The clock hides while editing. Teams' edit toolbar here also has Attach and "+" (OST shows Format and Emoji).
  - Not built yet: the scheduled message's Translation item, and Record video clip.

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
- **Attach menu, measured** (winpc 2026-11-12, OST group test):
  - A popover centred on the Attach button, its bottom at the button's top: 306.3 x 438.3, white, radius 4, shadow 16.
  - The search box (padding 7 10 5): 285 x 32, #F5F5F5, radius 4, a 14 px #616161 search glyph at 13.7, "Search cloud files" (14 px) at 42.7.
  - With no recent files: Teams' `document-clock-l-standard.svg` illustration (120 px at 92.6, 117.2) over "Your recent files suggestions will show up here soon." (14 px #424242, 200 wide, centred).
  - A full-width 0.67 line at 358.3, then the items (283 x 28, 32 apart, from 11 in; a 14 px glyph at 19, the label 14/600 #424242 at 46): "Attach cloud files" (cloud), "Upload from this device" (arrow up). A chat has no "Browse Teams and Channels".
  - **Attach cloud files** opens OneDrive's file picker in a dialog: `{OneDrive}/_layouts/15/FilePicker.aspx?app=Teams.Chat&scenario=FilesPersonalPicker&filePicker={"sdk":"8.0","title":"OneDrive","entry":{"oneDrive":{"recent":true}},"typesAndSources":{"mode":"files","pivots":{"teamsCloudStorage":false,"sharedLibraries":true}},"tray":{"commands":[{"key":"Attach","label":"Attach","action":"pick","primary":true},{"key":"Cancel","label":"Cancel","action":"close"}]},"selection":{"mode":"multiple"},"leftNav":{"enabled":true},"search":{"enabled":false},…}`.
    - Places: "OneDrive" title (the Navigation Pane button), Home, My files, Shared, Favorites, Browse by (People, Meetings, Media), Quick access, More places…. Home lists recent files: Name (with its place under it), Opened, Owner, Activity.
    - Rows have selection circles; "{n} selected ✕" at the bottom left; Attach (primary) and Cancel at the bottom right. My files has New folder and the view switch.
  - **Captured 2026-11-13** ("OST TEST 117/120" in OST group test, "OST TEST 118" in the OST layout test channel):
    - **The popover's files.** Opening it asks substrate `POST /search/api/v1/recommendations?setflight=recDisableExchangeAttachments,…` (Scenario `teamsDesktop.AttachFile`, the conversation's last 3 messages as `Microsoft.OutlookServices.Message` context: Id, Body, Sender/ToRecipients ExternalId, times).
      - Typing searches with `POST /search/api/v1/suggestions?scenario=slimpicker.compose&setflight=TurnOffMPLSuppressionTeams&domain=File` (`EntityType` File, Size 25).
      - Both were empty for ost-test1, so the result rows are unmeasured.
      - Nothing found shows `search-exclamation-l-standard` (120 at 92.3, 116.2) over "We couldn't find any results" (16/22 600 at 244.2) and "Check for spelling or try another search keyword" (12/16 #424242 at 274.2). Under them are two centred buttons, "Upload from this device" and "Attach cloud files" (12 px, 23.3 tall, padding 1 8, 0.67 #D1D1D1, radius 4, 12 apart from 306.2). The item list is hidden.
      - The box is 285 x 32 at 10, 7, with a 2 px brand underline while focused. Clear search is 24 x 23.3 at 260.3, 11.3.
    - **A channel** adds "Browse Teams and Channels" (people-team) between the two items, so the line and rows move up 32. It opens the same picker with `entry.sharePoint.byPath` at the channel's folder, whose trail reads `{team} › Documents › {channel}`. An empty folder shows "This folder is empty" (20/600 at 207.7) over `empty_files_v3` (256).
    - **The picker** is a 972.8 x 557.6 dialog (76% x 82% of the window), radius 8, over rgba(37,36,36,.75). It is #F5F5F5, with white content from x 82.
      - The rail is 68 wide; Navigation Pane widens it to 210 over the content ("OneDrive" 20/600, labels 14 at 52, "Browse by" / "Quick access" 14/600 headers, More places… 12/600 #115EA3). The open item is #115EA3 on #EBEBEB (36 x 36), with a 4 x 16 bar at x 4.
      - Home (`sp.RecentFileCollection.DeltaSync?top=500`, the files you opened) is a card (radius 12, 0.67 #F0F0F0) at 98, 78. Its columns Name / Opened / Owner / Activity (12/600 #424242) sit at 143.7 / 468.2 / 622.7 / 797.2. Its rows are 56: icon 32, name 14 over the site's title 12 #616161, the time as OneDrive's activity time, then "You edited this · Nov 6".
      - My files and folders have a #F5F5F5 header 43.7 (Name / Modified / Modified By / Activity 14/600 #616161) and 59 px rows: the name 14 #616161 over "{n} items" or the size (12 #8A8A8A), the cells #8A8A8A. A selected row is #CFE4FA.
      - Shared, Favorites and Meetings (`sp.OneDriveItemCollection.GetSmartCacheData` {"names":["calendarevents","sharedmeetingfiles"]}) were empty: 20/600 text at 119.7 over a 256 picture (`empty_shared_v3`, `empty_favorites_v3`, `empty_meeting_v3`).
      - People (`sp.PeopleCollection.GetCollaboratorsAsStream`) lists each collaborator with chips of their files (198 x 41.3, radius 6; 16 px icon, the name 12, a #F5F5F5 "18m ago" pill).
      - Media shows 265.8 x 149.5 pictures under date headings ("Nov 8 - Nov 9, 2026", 18/600).
      - The footer is 80: "{n} selected ✕" (radius 18, 0.67 #605E5C) at 24, 24; Attach (80 x 32, brand, radius 2; #F5F5F5 / #BDBDBD while nothing is picked) and Cancel.
    - **The compose box.** The picked file reads `{host}/_api/v2.0/shares/u!{url}?expand=site,driveItem(select=…,sharepointIds,publication,viewpoint/sharing,mainlink)` and `{site}/_api/v2.0/sites/root/items/{uniqueId}/driveItem/commands`, whose `invite.defaultLinkDescription` the card shows.
      - The card goes under the text (file-well, 13 in): 320 x 237.3, radius 6, 0.67 #E0E0E0 and a soft shadow.
      - Its #FAFAFA header is 56.7 tall: a 32 px icon at 16, 12; the name 14/600 at 60, 10.3 over the description (12 #424242, a button that opens Link settings with "People currently in this chat"); Remove attachment 32 x 30 at 274.7, 13.
      - Below the header is the `thumbnails/0/c960x540` picture (179.3 tall, #F5F5F5).
    - **Send, in a chat.** Teams finds the members (users/fetch), then `POST …/driveItem/invite` {"recipients":[{"email"}],"roles":["write"]} with `prefer: ReturnSpecificErrorCode,getDefaultLink`, `scenario: TeamsFiles` and `application: Teams_Maglev`. Without that prefer, SharePoint answers 400 "RequireSignIn and SendInvitation cannot both be false".
      - The reply's `value[0]` is the default link: `id`, and `link.webUrl`. On this tenant it is the Anyone edit link, created by the first such invite.
      - The `properties.files` entry has itemid = the list item's GUID, `fileInfo` (itemId = Graph's id, fileUrl, siteUrl, shareUrl and shareId from the invite), `fileChicletState` {serviceName "p2p", state "reference"}, state "reference", `chicletBreadcrumbs` from the site path ("personal" / "ost-test1_scnetsolutions_com"), permissionScope "Anyone", `sharepointIds` {driveId, listId, listItemUniqueId, siteId, siteUrl, webId}, and null publication/site values.
      - A "You've shared {name}" toast follows.
    - **Send, in a channel.** There is no invite. shareUrl and shareId are "", and serviceName is "teams".
- **Fun picker** (505584):
  - Popover above the button, aligned to its end.
  - Tabs All | Emoji | GIFs | Stickers, each only when its policy allows.
  - Search "Find something fun", label "GIFs powered by GIPHY".
  - GIF categories: Trending, Reactions, Greetings, Perfect, Welcome, Congratulations, Thank you, Excited.
- **Fun picker, measured live** (winpc, `unified-picker-content`, 2026-11-07):
  - **Frame**: 316 × 485, background #FAFAFA.
    - Tabs at y 2, 50 tall: All (x 19.1, 40.7 wide), Emoji (78, 59.3), GIFs (155.5, 50.9), Stickers (224.6, 72.4). Labels are 14 px at +10; the open one is 600 #242424, the rest 400 #424242.
    - A white body from y 53 (radius 6 6 0 0).
  - **Search**: 286 × 32 at (15, 68), #F5F5F5, radius 4. With a back button (32, at 15) it shrinks to 242 at x 59.
  - **All**:
    - headings "Emoji", "GIFs" and "Stickers" (14/500) at y 122.7 / 217.3 / 352.3, each with "See all ›" (`titlerow-end-button`, 83.2 × 31.3 at x 224.8, which opens that tab);
    - six recent emoticons (46 px cells from x 15, y 150.3);
    - three trending GIFs (89.3 × 86.3 at x 17.5 / 113.3 / 209.2, y 245; image 88 × 85, radius 6);
    - four recent stickers (69 px tiles, 3 apart, at y 380).
  - **Footer** (All and GIFs): at y 449, 36 tall. "GIFs powered by GIPHY" (12 px) at x 111.5, "View Terms" (12 px brand) at 241.4.
    - View Terms opens a popover: "When you search for images, your search terms are sent to GIPHY. To learn more, see GIPHY's Privacy Policy and Terms of Service."
    - Its links go to support.giphy.com/hc/{locale}/articles/360032872931-GIPHY-Privacy-Policy and …/360020027752-GIPHY-User-Terms-of-Service.
  - **Emoji**: the reaction picker's panel, 432.3 tall from y 52.7, with Customize; the org's "Custom" section is last (see `custom-emoji.md`).
  - **GIFs**:
    - categories: 139.5 × 76 tiles at x 15 / 160.5, 81 apart from y 115. The picture is `…/evergreen-assets/funstuff/giphy/assets/categories_bg/{name}.gif` under `rgba(0,0,0,.3)`, with the name 14/600 white at (15.7, 28).
    - results: two 140-wide columns (x 15 and 161, 6 apart), each item 140 × (140·h/w), radius 6; the title shows as a tooltip.
  - **Stickers**:
    - Recent: eight 69 px tiles, 4 a row, 3 apart, #F5F5F5, radius 6, the picture 59.7 inset 4.7. Editable stickers get an 18 px #575757 badge with a 12 px pencil at +43.6.
    - "Sticker Packs" with See all: 138 × 46 tiles (#F5F5F5, radius 6), the name 14/600 at +10 and a 26 px icon at +102.
    - Default recents: Clippy_HelloThere, OfficeDrama_HighFive, WordArt_Awesome, Octocorn_Coffee, Teamsquatch_Yes, grumpycat, Bee_Angry, Devs_Works_On_My_Machine.
  - **Caption editor** (editable stickers, inline in Stickers):
    - the captioned template centred at y 130, 195.3 wide;
    - a "Caption" box (286 × 94.7, #F5F5F5) at y 288, pre-filled with the default caption;
    - Cancel and **Done** (138 × 31.3) at y 395.3.
- **Where the content comes from**:
  - **GIFs**: `POST {middleTier}/beta/commands/com.microsoft.teamspace.inputextension.giphy/execute?version=1.0` with `[{name:"query"},{name:"rating"},{name:"limit","27"},{name:"lang"}]` (services-giphy 757304).
    - An empty query is trending.
    - The result is `[{result:[{composeValue, fieldValues:[title, image, previewImage, previewImageFW, width, height, …]}]}]`.
    - Rating by the tenant's `giphyRatingType`: Strict → y, Moderate → g, NoRestriction → pg-13.
  - **Stickers**: Teams' own catalogue (components-compose-extensions; names in `funstuff` strings), 41 packs and 674 stickers, the EDU packs only for Teacher/Student licences.
    - Pictures come from `teams.public.onecdn.static.microsoft/evergreen-assets`:
      - previews `funstuff/stickers/{locale}/assets/{pack}/Preview/{file}?v=5` (memes: `funstuff/meme/assets/Preview/…`);
      - sent files `stickerassets/{pack}-250x250[/en-us]/{file}?v=5` (memes `-500x500`).
- **What's sent** (each captured from Teams' own messages):
  - **Emoticon**: `<span title="Surprised" type="(surprised)" class="animated-emoticon-20-surprised" itemscope=""><img itemscope="" itemtype="http://schema.skype.com/Emoji" itemid="surprised" src="https://statics.teams.cdn.office.net/evergreen-assets/personal-expressions/v2/assets/emoticons/surprised/default/20_f.png" title="Surprised" alt="😮" style="width:20px; height:20px"></span>`.
  - **GIF**: `<p>&nbsp;</p>` + `<img src="{giphy.gif}" width height alt="{title} (GIF Image)" style="height:auto; margin-top:4px; max-width:100%">` + `<p>&nbsp;</p>`. The size fits 444 × 250 (480 × 270 went as 444 × 250).
  - **Sticker**: the same frame, with `<img src="{stickerassets URL}" height="180" alt="{name}" width="180" itemtype="http://schema.skype.com/Sticker">`.
  - **Captioned sticker**: drawn by the client, uploaded to AMS, and sent as `<img src="{ams}/v1/objects/{id}/views/imgo" width="240" height="180" itemscope="image/png" itemtype="http://schema.skype.com/AMSImage" alt="Sticker image, {caption}" id="{id}" itemid="{id}">`.
    - The service prefixes the element id with `x_`.
    - The AMS calls need a User-Agent with `Teams/{version}/{platform}` (Teams desktop sends …/49), or they fail with 400 "platform id could not be created".

### A file in a message (measured on winpc, 2026-11-13, OST TEST 121)
- **Card.** 320 x 229.33, radius 6, a 0.67 #E0E0E0 edge and the shadow (0 0 2 rgba(0,0,0,.12), 0 1 2 rgba(0,0,0,.14)), 16 in from the bubble's edge. A 48.67 #FAFAFA head with a 0.67 #E0E0E0 line under it, then the preview: 318.67 x 179.33 (16:9) on #F5F5F5, the c960x540 thumbnail top-aligned.
- **Head.** "Main actions" is 238.67 x 44 at 8, 2, radius 8, and turns white on hover. Inside it:
  - the 32 px file-type icon at 4, 6;
  - the name (14/20 semibold) at 44, 4, cut at the end;
  - the location under it (12/16 #616161), from `chicletBreadcrumbs`: "{team} > {channel}" ("personal > ost-test1_…" for a OneDrive file). A SharePoint list (splist) shows its team alone unless the team is "personal". The line is hidden unless both names are set. While a file uploads, or for an external file, Teams shows status text here instead.
  - Clicking the head or the preview opens the file in Teams' viewer (below).
- **Share** (`quick-share-action-button`): 32 x 31.33 at 246.67, 8.33, with a 20 px #616161 glyph. It opens Share this file. The card in that dialog starts from the file's default link, the `driveItem/commands` description ("Anyone with the link can edit" for ost-share-test.txt), and the box hints "Add a message (optional)".
- **More actions (···):** the same size, radius 6. Its Fluent menu is 180 wide, padding 4, radius 4, with rows 32 tall and 2 apart. The label is 14/20 #424242 at 30; the menu's top-right sits under the button. Its items:
  - **Open in Browser:** opens the file's link in the browser.
  - **Download:** downloads the file.
  - **Share:** as the Share button.
  - **Copy link:** OneDrive's share dialog in copy mode, which goes straight to "Link copied" with what the link does ("Anyone with the link can edit") and Settings. It reuses the file's existing link.
  - **Favorite / Unfavorite** (star / filled star): `POST {tenant}-my.sharepoint.com/_api/v2.1/favorites/followedListItems/oneDrive.add` (or `.remove`) with `{"value":[{"siteUrl":"<site>/","url":"<file>"}]}`. The toast reads `Added "{name}" to OneDrive Favorites`, or "Removed from OneDrive Favorites" with Undo. The menu then reads Unfavorite, and Graph's `/me/drive/following` agrees.
- **The viewer.** It fills the app's area right of the app bar, over the chat list and the conversation, below the title bar.
  - Its header is 61 tall, white, with a 0.67 #E0E0E0 line under it. The 20 px type icon is at 20, 20 and the name (16.38/23.4 bold) at 60.
  - Close (96 x 32, white, a 0.67 #D1D1D1 edge, radius 4, 14 semibold) is 39 from the right. "More attachment options" (32 x 32, a 16 px ···) is 2 from the right. It opens the card's menu 4 under the button.
  - The file shows in OneDrive's `embed.aspx` on #FAF9F8. A text file gets a white name strip (30 tall, 20 in, the name 14 px at 10, 6) over Monaco: line numbers right-aligned in 38 (Consolas 14/19; the current line's #0B216F, others #237893), the text at 64, and the current line framed 2 px #EEEEEE. Monaco's minimap is not drawn.
  - Office files are Word / Excel / PowerPoint for the web inside the embed. OST shows them as PDF pages (Graph's conversion), as its Preview does.
- **Toast.** Teams' in-app toast is 288 wide. The title (14/20 semibold) wraps in 202.67 at 36.67, 12.67. Undo (14 px #4F52B2) sits 11 under it, and the card is then 12.67 deeper: 46 tall for one line, 65.33 for two, 96.33 with Undo.

### Cards in a message (measured on winpc, 2026-11-13, OST TEST 122–125)
- **Several cards** in one message stack 8 apart, each 452 wide (hero, thumbnail, list and connector cards). A hero card with a title, subtitle, text and one row of buttons is 161.33 tall; its buttons sit 8 under the text.
- **List card item icons:** 32 x 32 (stretched) at the item's start, 0.4 below its title's top. The text sits 12 after the icon (44 in). Rows keep their height (60 for a result item).
- **Connector card:**
  - The chat service stores its markdown as HTML (`<p>`, `<strong>`, `<em>`, `<a>`, `<ul><li>`). Links are #4F52B2 without an underline. Lists are indented 40, with 14 above and below.
  - The body is a column 8 apart: title, text, sections. The frame ends 16.6 under the last item.
  - A section is a column 10 apart, in this order:
    - its title;
    - the activity row, which stays (0 tall) in a section without an activity. The activityImage is 52 x 52, stretched, and the three lines sit 62 in, 30 apart;
    - its text;
    - its images (160 x 120, stretched, 10 apart);
    - its facts, with 10 more under the last.
  - potentialAction (OpenUri, ActionCard) shows no buttons.
- **Adaptive Card Carousel** (`enableAdaptiveCardCarousel`): one page at a time, at the tallest page's height. 12 lower comes a 24 px row, centred, with 6 between its parts: Previous (‹ 20 px #424242), the dots, and Next (›). Each dot is a 24 x 24 button: the current one a 16 x 8 pill, the others 8 x 8 at 65% opacity, #242424. The element ends 16 under the row. Previous and Next wrap around.

### Bot card actions (captured on winpc, 2026-11-13, OST TEST 126: a Polls poll)
- **Invoke.** `POST {chat service}/v1/agents/{bot MRI}/invoke` with the skype token. The body is `{name?, appId?, messageType, value, imdisplayname, userAadToken, serverMessageId, clientMessageId, conversation: {id}}`.
  - Nulls are dropped.
  - `appId` is the bot's app from the catalog (definitionsv2 `bots[].id`).
  - `userAadToken` is the middle tier's token (api.spaces.skype.com).
  - An automatic refresh adds `X-MS-AutoRefreshRequestInThread: {thread}`.
- **Action.Submit with `msteams.type: "invoke"`.** There is no name. The value is the action's data without `msteams`, with the card's inputs merged over it (the poll: `{data: {Type: "QuickPoll.SubmitVote", …}, choice: "1"}`).
  - The reply is an empty 200.
  - The card then gets Teams' response bar: 28 tall, #E6E6E6, a 0.67 #E0E0E0 line on top, an info icon at 16, "Your response was sent to the app" (14 px #424242) at 41.33, and Close.
  - The bot edits its results message, which then shows "Edited".
- **Action.Execute and `refresh`.** The name is `adaptiveCard/action` and the value is `{action: {type: "Action.Execute", verb, data, title?}, trigger: "automatic" | "manual"}`. The reply is `{statusCode, type, value}`:
  - `application/vnd.microsoft.card.adaptive`: a card that replaces the message's. The meta line then adds "Updated".
  - `…activity.message`: text for the bar.
  - `…error`: an error for the bar.
- **When a card refreshes.** It refreshes once a session, for the users in `refresh.userIds` (everyone when it lists none). The Polls card lists only its author, who gets `fetchAuthorVoteCard`.
- **How the message looks.**
  - The sender line reads "{onbehalfof name} via {bot}" ("OST Test 1 via Polls").
  - The bot's picture is its app's icon in a 32 px square with 4 px corners.
  - A bot's card alone has no bubble: just the 448-wide card (#FAFAFA, radius 6, a soft shadow).
  - A grouped message that was edited shows "Edited" (12 px #616161) above its bubble.
- **Not yet in OST:** a plain Action.Submit (not an invoke), messageBack, and Action.Submit/Execute from a task module.

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
- **Extra rows**: "Add agent to the chat / channel" (opens the in-context Store, store.md §3), "Add someone to the chat" (group chats), "Share someone's contact info". Name suffixes "(You)" and "(External)". Rows sit 5 apart; Everyone, Add agent and Share are 49.3 tall, Add someone 48.7, people 47.3 (measured on winpc, 2026-11-09).
- **Everyone row rules** (worker `getEveryoneActionItem`):
  - It is offered when (members − 1) fits the chat's limit.
  - When it would only fit the larger (meeting) limit, it is shown disabled, with the tooltip "Not available for chats over 1,000 users." (peoplePicker).
  - Above People `atMentionEveryoneBannerThreshold` it carries the banner `AtMentionEveryoneOverThreshold`: messaging `tmp_at_mention_everyone_over_threshold_banner_message_mf`, "{n, plural, =1{1 person will be notified} other{# people will be notified}}".
  - Not built yet: the banner's look couldn't be measured, because no test chat has that many members.

### Measured (winpc, 2026-11-07)
- Typing "@" opens `AutocompletePopup-Mentions`: 300 wide, white, radius 4, a drop-shadow, its bottom at the caret line.
  - "Suggestions" (14/20, #424242) sits at (20.7, 10.7).
  - Person rows (`autocomplete-picker-item-{name}`, option) are 47.3 tall: a 32 px avatar at 20.3, the name 14/20 and email 12/16 at 60.3. The active row is #E6E6E6.
  - Then Everyone ("Notify everyone in the chat"), Add agent to the chat, Add someone to the chat (`chat-add-members`) and Share someone's contact info.
  - In a group chat, "@Ran" suggested only chat members.
- A picked person goes in as **one mention token per word**: `<mention mri="…" type="person">Randy</mention>&nbsp;<mention …>Northrup</mention>`, coloured #4F52B2, weight 400.
- Wire format (OST-sent and rendered by Teams as "Mentioned Randy"):
  - the content has `<span itemtype="http://schema.skype.com/Mention" itemscope="" itemid="0">Randy</span>&nbsp;<span … itemid="1">Northrup</span>`;
  - `properties.mentions` is a JSON string, one entry per span: `{"@type":"http://schema.skype.com/Mention","itemid":N,"mri":"8:orgid:…","mentionType":"person","displayName":"Randy"}`.

### Share someone's contact info (measured on winpc, 2026-11-07, "OST TEST 64")
- **Picker row.** It is always last: the contact-card icon (20) at 20.3, text at 59.7, 49.3 tall.
- **Dialog** (`chat-share-contact-popup`). 402 wide, radius 4, 16.7 padding.
  - Title "Share someone's contact info in the message" (14/20).
  - A tag picker at (16.7, 46.7): 368.7 × 33.3, #F5F5F5, radius 4, 12 in, a brand underline while focused, placeholder "Enter name". With a tag it is 38.7 tall.
  - The hint "They won't be @mentioned or notified" at 24.7.
  - Cancel and OK (96 × 31.3) at (177.3 / 281.3, picker bottom + 54). OK is disabled (#F0F0F0 / #BDBDBD) until someone is picked.
- **Results.**
  - A white list under the picker: 368.7 wide, radius 4, menu shadow.
  - Rows are 346.7 × 50, starting 4 in, 2 apart, with the active row #F5F5F5.
  - Each row has a 32 px avatar at (12, 9), the name 14/20 #424242 at (60, 6.5) and a second line 12/16 #616161 at 27.5, with the typed part bold.
- **Tags.** A white pill 25.3 tall holding a 24 px avatar, the name and a 12 px dismiss. Several people can be picked.
- **Wire format.** For each contact:
  - `<span title="ID card" type="(idcard)" class="animated-emoticon-20-idcard" itemscope="Share_Contact_Card">`;
  - inside it, an Emoji img with `itemid="idcard"`, Teams' fixed 64 px PNG as a `data:` src, `alt` "🪪";
  - then `<span itemtype="http://schema.skype.com/Mention" itemscope="Share_Contact_Card" itemid="N">{name}</span>`;
  - its mention has `mentionType` "share-contact".

  It never counts as mentioning that person. OST's "OST TEST 65" matched it byte for byte.
- **Rendering.** The contact-card-20 icon in brand #4F52B2, then the name as a mention (#4F52B2, opens the profile card).
- **Mention colour.** Received mentions are BrandForeground1 #4F52B2 (measured), not #5B5FC7.

### Channels (measured on winpc, 2026-11-07, OST Test Team > General)
- **The picker in a channel.**
  - "Suggestions" shows even with a query.
  - "@" alone offers only "Add agent to the channel" and "Share someone's contact info".
  - Typing matches the team ("OST Test Team", subtitle "Team") and the channel ("General", subtitle "Channel"). Both rows show the team's square picture (32, radius 4).
  - The typed part of a name is bold (700). "@cha" matches the current channel through the word "channel".
  - Only team members are suggested. "@Ran" found nobody, since Randy isn't in the team.
- **Wire format** (Teams-sent "OST TEST 60"; OST-sent "OST TEST 62" and "OST TEST 63" are byte for byte the same).
  - A channel mention is one span. Its mention has `mentionType` "channel", `mri` = the channel's thread id and `displayName` = the channel name.
  - A team mention is one span holding the whole team name. Its mention has `mentionType` "team", `mri` = the team's thread id (the General channel's id) and `displayName` = the team name.
  - Teams' editor holds a team as one token per word, but it sends one span.
- **Post highlight** (763654 `L`). The first match wins:
  - pinned: green, pin icon;
  - mentions you: orange, mention icon. Important or Urgent replace it when the message has them;
  - @Everyone from someone else: orange;
  - Important: red, "!" icon;
  - Urgent: red;
  - a channel mention: orange, channel icon, aria "Channel message";
  - a team mention: orange, team icon;
  - your own post: a brand #4F52B2 bar with no badge.
- **Highlight geometry.**
  - The bar is a 4 × 32 rect at (4, 16) in the card, rx 2. A reply's bar is 4 × 20 beside its avatar.
  - The badge (`channel-badge` and the like) is a 24 px circle centred on the card's right edge, 20 down, with shadow 0 0 2 / 0 2 4. It holds a white 16 px icon: Fluent's 20 px icon drawn with viewBox "2 2 16 16".
  - Orange is #DA3B01.

### Tags (measured on winpc, 2026-11-09, OST Test Team > General, "OST TEST 69")
- **Source.** The picker reads the team's tags from `GET {csa}/api/v1/teams/{teamThreadId}/tagCards?tagType=any` (chatsvcagg token): `tagCards[] {tagId, tagName, memberIds, memberCount, tagType, currentMemberIsPartOfTag}`.
- **Picker row.** After the team and channel rows, matched by a word of the tag's name. 47.3 tall like a person row: a 32 px circle #C5CBFA holding the Tag 20 icon in #444791, the name 14/20 with the typed part bold, and "1 person" / "N people" (12/16) under it. (The code's "Channel tag | # people" label did not show on this build.)
- **Compose.** The tag is one token in BrandForeground1.
- **Wire format** (Teams-sent "OST TEST 69"; OST-sent "OST TEST 70" rendered the same):
  - the content keeps the editor's wrapper: `<readonly class="skipProofing" itemtype="http://schema.skype.com/Mention" spellcheck="false"><span itemtype="http://schema.skype.com/Mention" itemscope itemid="0">OST test tag</span></readonly>`. The service stores it without the wrapper;
  - its mention has `mentionType` "tag", `mri` = the `tagId` and `displayName` = the tag name.
- **Rendering.** A mention of a tag you are in (Teams' `currentUserTagIds`, from `currentMemberIsPartOfTag`) mentions you: the name in the mention-me orange bold, and the post gets the orange @ badge. Other tags render as ordinary mentions.
- **Activity.** Its feed item has `activityType` "mention" and `activitySubtype` "tag" (the `mention_tag` processor). The title is "{name} mentioned {tag}", the tag from `activityContext.tagname`. Only the Tag mentions filter shows it.

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
- [ ] "+" flyout items; fun picker tabs.
- [x] Attach menu (2026-11-13): the popover, the cloud file picker, the compose card, and the send in chats and channels, all as Teams. OST TEST 119 and 121 store the same records as Teams' 120 and 118. Not yet: the picker's command bar, People's collaborators, Media's headings and controls, the card's Link settings, and the suggestion rows (TASK-0130).
- [x] A file in a message (2026-11-13): Teams' card with the location and preview, Share (Share this file from the default link), and the ··· menu (Open in Browser, Download, Share, Copy link, Favorite / Unfavorite with Teams' toasts and Undo). Opening the file shows Teams' viewer: the header with Close and ···, and OneDrive's embedded text view. Office files show as PDF pages, not Office for the web.
- [ ] Delivery options (Urgent disabled above 20 members), schedule send on right-click of Send, Enter behaviour and setting, hint text.
- [ ] Pre-send checks, 90112-byte message limit and its error text, draft save, debounced at 400 ms.
- [ ] @mention rules: Everyone limits (channel, team and tag mentions done).
- [ ] Message and compose keyboard shortcuts in §20.
