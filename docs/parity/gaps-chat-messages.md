# Gap list: chat list & conversation header, message timeline & composer

Compares OST (branch `desktop/foundation`, 2026-11-06) with:
- `docs/spec/chat-list-and-header.md` (cited "CLH §n") and `docs/spec/messages-and-composer.md` (cited "MC §n"), both taken from Teams' client code;
- the inventories `docs/parity/chat.md` ("chat.md §n") and `docs/parity/teams-channels.md` ("TC §n"). Where they disagree, the specs win.

Each item was checked against the OST code named in it. "absent" means no code for it exists in `desktop/qml/*`, `desktop/src/backend.rs` or `src/api/*`.

Priority: **[P1]** core everyday behaviour · **[P2]** common · **[P3]** rare, flag-gated or licence-gated.

Format: `- [ ] [Pn] behaviour — Teams: … — OST: … (ref: …; OST: file:line)`

---

## A. Chat list

### A1. Rail width and layout
- [ ] [P2] Responsive list width — Teams: 0 below 640 px window, 280 px at ≥640, 320 at ≥1280, 360 at ≥1500 — OST: always 320 px (ref: CLH §1; OST: desktop/qml/Theme.qml:81, ChatList.qml:24)
- [ ] [P2] Drag-resizable divider — Teams: `role=slider` clamped 280–400 px; ArrowLeft/Right resize it, double-click resets; chat.md: Ctrl+Alt+Enter focuses it, Ctrl+Shift+Enter resets it — OST: absent; the edge is a 1 px line (ref: CLH §1, chat.md §1; OST: ChatList.qml:54)
- [ ] [P3] Resize smaller / Resize larger buttons on the divider (`enableResizableSlotsPolishedCursor`) — OST: absent (ref: CLH §1; OST: absent)

### A2. List header and "More list options"
- [ ] [P2] Header button order and icons — Teams: title, ···, **Filter** toggle (filter icon, filled while open), New message, New items ▾ — OST: same order, but the filter button uses a magnifier icon (search-20) and never shows a filled state (ref: CLH §2, §2.2; OST: ChatList.qml:94-97)
- [ ] [P2] Filter toggle labels — Teams: "Show filter text box" / "Close filter text box"; the tooltip shows Ctrl+Shift+F only while the box is closed — OST: one static accessible name and no tooltip (ref: CLH §2.2; OST: ChatList.qml:95)
- [ ] [P2] ··· menu contents — Teams: **Mark all as read** (split item; its submenu has All / All chats / All channels / All communities), **Collapse all sections** (Alt+Q), divider, **Customize view** ("Try it" badge), divider, **Your teams and channels**, **Your communities** — OST: "Mark all as read", "Collapse all groups", "Expand all groups" ("Expand all" doesn't exist in Teams) (ref: CLH §2.1, TC §1; OST: ChatList.qml:85-91)
- [ ] [P2] Mark all as read scope and service — Teams: `markAllAsReadByAppName(appType)` clears every chat, channel and community item, plus section badges — OST: marks only the ids in its local unread set, one consumption-horizon PUT per chat (ref: CLH §2.1; OST: backend.rs:4099-4116, src/api/messages.rs:749-771)
- [ ] [P2] Shift+Esc confirmation — Teams: dialog "Are you sure you want to mark all chats, channels, and communities as read?" with a "Don't ask again" checkbox (saved in `skipMarkAllAsReadConfirmDialog`) and Confirm/Cancel; from the menu it runs with no dialog — OST: Shift+Esc runs at once with no dialog (ref: CLH §2.1; OST: Main.qml:66)
- [ ] [P2] Collapse all sections persisted — Teams: `setConversationFoldersExpandedState(isExpanded:false)` saved via the conversation folders service — OST: local booleans, lost on restart (ref: CLH §2.1, §3; OST: ChatList.qml:49-52, 89)
- [ ] [P3] Customize view → Settings (Combined/Separate) — Teams: opens Settings with the search box focused; Separate view splits Chat and Teams apps — OST: absent (ref: CLH §2.1, chat.md §1, TC §1; OST: absent)
- [ ] [P2] "Your teams and channels" page — Teams: opened from the ··· menu and from "See all your teams" — OST: the "See all your teams" text has no action, and the page doesn't exist (ref: CLH §2.1, §3, TC §5; OST: ChatList.qml:310-319)
- [ ] [P3] Dot badge on ··· while "new items to try" is on (≤7 days); aria "More list options. New items to try" — OST: absent (ref: CLH §2.1; OST: ChatList.qml:78-80)

### A3. Filter text box
- [ ] [P2] Placeholder / aria — Teams (unified): "Filter by person, chat or channel name" — OST: "Filter by name" (ref: CLH §2.2; OST: ChatList.qml:163-164)
- [ ] [P2] Text box sits above the pills (both visible) — Teams: animated in above the pill row — OST: the box replaces the pills while open (ref: CLH §2.2; OST: ChatList.qml:118, 149)
- [ ] [P3] Input limits — Teams: refuses input over 100 characters and debounces 250 ms before refiltering — OST: no limit, refilters on every keystroke (ref: CLH §2.2; OST: ChatList.qml:161)
- [ ] [P2] Clear button — Teams: aria "Clear filter text"; it clears the text and keeps the box open — OST: aria "Close filter"; it closes the box (ref: CLH §2.2; OST: ChatList.qml:173-175)
- [ ] [P2] Empty result — Teams: "We didn't find any matches." plus a **Clear filters** button, and screen readers hear "Filter active" — OST: empty sections and no message (ref: CLH §2.2; OST: absent)

### A4. Filter pills
- [ ] [P1] Pill set and order — Teams (live): **Unread, Channels, Chats, Meeting chats**, then Communities when licensed — OST: Unread, Channels, Chats only (ref: CLH §4, chat.md §2, TC §2; OST: ChatList.qml:122)
- [ ] [P1] Unread combines with one category — Teams: categories are single-select and Unread stacks with any one of them — OST: one chip at a time, so Unread+Chats is impossible (ref: CLH §4, chat.md §2; OST: ChatList.qml:27, 33, 133)
- [ ] [P1] Unread pill includes channels — Teams: unread channels stay in the list under Unread — OST: Unread hides the whole Teams-and-channels section (ref: CLH §4; OST: ChatList.qml:45)
- [ ] [P2] Width-based overflow — Teams: pills that don't fit move to a second row behind **More filters** / **Fewer filters** (hidden when nothing overflows); selected pills stay visible — OST: a "More filters" chevron that is always shown and opens a menu with the same three items plus "Clear filters" (ref: CLH §4; OST: ChatList.qml:178-197)
- [ ] [P2] Filter choice persisted — Teams: `updateSimpleCollabStickyFilter`, restored next session — OST: in-memory only (ref: CLH §4, chat.md §2; OST: ChatList.qml:27-28)
- [ ] [P2] Unread empty state — Teams: "You're all caught up!" with Clear filters — OST: absent (ref: CLH §4; OST: absent)
- [ ] [P3] Muted / Unmuted / @Mentions / Communities pills (config- or flag-dependent) — OST: absent (ref: CLH §4, chat.md §2; OST: absent)
- [ ] [P2] Meeting-chats and Muted shortcuts Ctrl+Alt+B / Ctrl+Alt+Q — OST: only U/A/C/Z exist (ref: CLH §6, chat.md §2; OST: Main.qml:67-70)

### A5. New message, New items ▾, new chat
- [ ] [P2] New items ▾ menu — Teams (unified): New message (Ctrl+N), New message in new window (Ctrl+Shift+N), New channel, [New storyline post], divider, Join team, New team, divider, [Join communities, New community], divider, New section — OST: one item labelled "New chat" (ref: CLH §2.3, TC §1; OST: ChatList.qml:109)
- [ ] [P2] New item label — Teams (rename flag live on): "New message" — OST: the menu says "New chat" (the button's accessible name is right) (ref: CLH §2.3; OST: ChatList.qml:100, 109)
- [ ] [P2] "To" searches people, chats, channels and tags — Teams: one compose surface for chats and channel posts — OST: the placeholder promises "name, chat, channel or tag" but only people are searched (ref: chat.md §6, TC §1; OST: NewChat.qml:114, 147, backend.rs:2419)
- [ ] [P3] Open new chats in a pop-out window (`alwaysPopOutNewChat`, Ctrl+Shift+N) — OST: absent (ref: CLH §2.3, chat.md §5; OST: absent)
- [ ] [P3] Group limits in new chat — Teams: 250 members, 200 added at once — OST: no checks (ref: chat.md §6; OST: NewChat.qml:27-39)

### A6. Sections and Quick views
- [ ] [P1] Sections come from the server — Teams: `{csa}/api/v1/teams/users/me/conversationFolders` decides membership and order (Quick views, Favorites, user sections, Chats, Meeting chats, Muted chats, Teams and channels, Communities) — OST: fixed client-side groups; Favorites comes from the legacy `favorites` user property (ref: CLH §3, §5.2; OST: ChatList.qml:208-321, backend.rs:994-1008, src/api/messages.rs:931-961)
- [ ] [P1] Custom sections — Teams: New section / Rename / Remove dialogs with the exact strings, duplicate-name error, emoji icon, and limits of 50 sections × 50 items — OST: absent (ref: CLH §3.2, chat.md §3, TC §3; OST: absent)
- [ ] [P2] Section ··· menu (and right-click) — Teams: Start reordering, View ▸ All/Unread only, Sort ▸ (Custom/Most recent/A-Z), Rename/Remove, Teams section Display ▸ / Hide inactive channels / Your teams and channels — OST: headers only toggle (ref: CLH §3.1, TC §3; OST: ChatList.qml:391-412)
- [ ] [P2] "See more" paging — Teams: Chats shows 25, then 25 more per **See more** (20 when Meeting chats exists); Meeting/Muted 5 then 10 — OST: one load of 50 chats, no See more (ref: CLH §3, chat.md §1; OST: backend.rs:967, 993)
- [ ] [P2] Muted chats system section (on by default) and Meeting chats section (off by default) — OST: absent (ref: CLH §3, chat.md §3; OST: absent)
- [ ] [P2] Followed threads quick view (live shows Mentions, Followed threads, Drafts) — OST: Mentions and Drafts only (ref: CLH §3, chat.md §4, TC §2; OST: ChatList.qml:212-223)
- [ ] [P2] Mentions view opens the message in context, in a right-side pane where you can react or reply — OST: opens the whole chat beside the list (partly done) (ref: chat.md §4, TC §2; OST: Main.qml:1594-1601)
- [ ] [P3] Quick view menu — Teams: Open in new window, Start reordering, Show ▸ Always / When unread, Hide; the Quick views header goes bold when a view is unread — OST: absent (ref: CLH §5.7, chat.md §4; OST: ChatList.qml:366-388)
- [ ] [P3] "New" badge on quick views for 14 days (not on exempt slices) — OST: absent (ref: CLH §3; OST: absent)
- [ ] [P3] Copilot row at the top (licence) and Communities section — OST: absent (ref: CLH §3; OST: absent)
- [ ] [P2] Load errors — Teams: "We ran into a problem getting your chats and channels." with Retry — OST: logs only (ref: CLH §3; OST: backend.rs:2663)

### A7. Teams and channels tree
- [ ] [P1] Only shown channels are listed — Teams: hidden channels are left out, with "See all channels" per team, and teams with no shown channel are left out — OST: lists every channel Graph returns (ref: CLH §3, TC §4; OST: src/api/teams.rs:74-118, ChatList.qml:284-307)
- [ ] [P1] Channel unread state — Teams: bold channel name, a dot, "@" for mentions, and the team row bold while collapsed — OST: unread channel ids are fetched but channel and team rows never show them (ref: CLH §5.1, TC §1/§4; OST: src/api/messages.rs:988-1010, ChatList.qml:286-306)
- [ ] [P2] Team expand/collapse saved on the server (debounced 500 ms, failure toasts) — OST: local, every team starts expanded (ref: CLH §3; OST: ChatList.qml:251, 280)
- [ ] [P2] Channel order — Teams: General first, then A–Z within each team — OST: Graph's order (ref: TC §3/§12; OST: src/api/teams.rs:95-102)
- [ ] [P2] General row reads as the team name where shown alone (`enableSimpleCollabTeamNameOverGeneralChannel`, live on) — OST: always the channel name (ref: CLH §3; OST: ChatList.qml:297)
- [ ] [P2] "Teams and channels" jump bar when the section is scrolled out of view (bold or "@" when unread) — OST: absent (ref: CLH §3, chat.md §1, TC §1; OST: absent)
- [ ] [P2] Private, shared and archived channel icons — OST: absent (ref: TC §4; OST: ChatList.qml:286-306)
- [ ] [P3] "New" badge on newly joined teams and never-opened channels — OST: absent (ref: CLH §5.1; OST: absent)

### A8. Row content
- [ ] [P2] Brand dot only for unread **and unmuted** chats; number badges on sections and teams — OST: a dot on every unread chat, no number badges, and mute state not read (ref: CLH §5.1, chat.md §5; OST: ChatList.qml:352-358)
- [ ] [P2] Charms: Followed icon, meeting-in-progress/huddle icon, "@" mention marker — OST: absent (ref: CLH §5.1, chat.md §17; OST: ChatList.qml:325-363)
- [ ] [P2] Draft row state — Teams: a chat with only a local draft shows the preview "Draft" and a draft icon; empty drafts are auto-discarded — OST: `draftIds` is passed in but never used (ref: CLH §5.1, chat.md §4/§10; OST: ChatList.qml:13, Main.qml:1582)
- [ ] [P2] Typing indicator in the row (`enableSimpleCollabLeftRailTypingIndicator`, live on) — OST: absent (ref: CLH §5.1; OST: absent)
- [ ] [P3] Message previews and timestamps (off by default in unified; Settings toggles) — OST: no setting and no rendering (ref: CLH §5.1, chat.md §1; OST: ChatList.qml:342-350)
- [ ] [P3] "(External)" / "(SMS)" label and trust badges — OST: absent (ref: CLH §5.1, chat.md §6; OST: absent)
- [ ] [P3] Muted group chat shows a mute icon in place of the group image — OST: absent (ref: chat.md §5; OST: absent)
- [ ] [P2] Hover shows a ··· button ("More chat options", "More channel options", "More team options") — OST: hover only tints the row (ref: CLH §5.1; OST: ChatList.qml:331-334)

### A9. Chat ··· / right-click menu (whole menu absent)
- [ ] [P1] The menu itself (hover ··· and right-click, opens below the row, closes on scroll), in Teams' classic order — OST: absent (ref: CLH §5.4, chat.md §5; OST: ChatList.qml:325-363)
- [ ] [P1] Mark as read / Mark as unread — Teams: `setConversationConsumptionHorizon` (+ bookmark when marking unread); screen readers hear "Chat marked as unread" — OST: absent (ref: CLH §5.4, chat.md §5; OST: absent)
- [ ] [P1] Mute / Unmute (not the self chat) — OST: absent (ref: CLH §5.4, chat.md §5; OST: absent)
- [ ] [P2] Move to section ▸ (destinations, New section, Remove from section) and Remove from section — OST: absent (ref: CLH §5.4, chat.md §3/§5; OST: absent)
- [ ] [P2] Hide / Unhide (hidden until a newer message arrives) — OST: absent (ref: CLH §5.2, §5.4, chat.md §5; OST: absent)
- [ ] [P2] Leave — Teams: only with ≥3 members, not for 1:1/self/bot, and not for the meeting creator; the dialog has a "remove chat history" checkbox — OST: absent (ref: CLH §5.4, chat.md §5; OST: absent)
- [ ] [P2] Delete / "Remove chat history" — Teams: 1:1 and bot chats, and group chats only when you can't leave (<3 members); asks for confirmation — OST: absent (ref: CLH §5.4, §7.4, chat.md §5; OST: absent)
- [ ] [P2] Open in new window (pop-out chat; also Ctrl+Enter on the row and double-click) — OST: absent (ref: CLH §5.4, §6, chat.md §5; OST: absent)
- [ ] [P3] Copy link with toast "Copied to clipboard" — OST: absent (ref: CLH §5.4; OST: absent)
- [ ] [P3] Notify when available / Turn off notifications (1:1) — OST: absent (ref: CLH §5.4; OST: absent)
- [ ] [P3] Block / Unblock (1:1), Block bot conversation, Manage apps, Set workflows, Report a concern (meeting) — OST: absent (ref: CLH §5.4, chat.md §5; OST: absent)

### A10. Channel and team ··· menus
- [ ] [P2] Channel ··· menu — Teams: Open in new window, Channel notifications, Move to section, Hide/Show, Add members, Share channel, Edit channel, Manage channel, Manage tags, Copy link, Get email address, Workflows, Recommend, Go to team, Leave, Archive/Restore, Delete, each with its permission rule — OST: absent (ref: CLH §5.5, TC §12; OST: ChatList.qml:286-306)
- [ ] [P2] Team ··· menu — Teams: Hide all channels (with confirmation), Add member, Add channel, Manage team, Manage tags, Copy link, Archive/Restore, Leave, Delete — OST: absent; tapping the row only toggles it (ref: CLH §5.6, TC §8; OST: ChatList.qml:280)
- [ ] [P3] Community menu — OST: absent (ref: CLH §5.7; OST: absent)

### A11. List data rules
- [ ] [P2] Hidden chats rule — Teams: a hidden chat stays out until a newer message; declined meeting chats are hidden; temp-hoist when selected (30 s for channels) — OST: no hidden rule; every conversation the list call returns is shown (whether the CSA `mychats` view already drops hidden chats is unverified) (ref: CLH §5.2; OST: src/api/chat.rs:465-517)
- [ ] [P3] Snapshot-and-sort when an item is selected (`enableSnapshotAndSortOnConversationSelect`) — OST: the list re-sorts on every reload (ref: CLH §5.2; OST: backend.rs:2646-2670)
- [ ] [P2] Unread detection covers only the first 100 conversations and only Text/RichText last messages — Teams: the consumption horizon against the last message, with no message-type limit — OST: `pageSize=100`, other message types count as read (ref: CLH §5.1; OST: src/api/messages.rs:964-1010)

### A12. Reordering and keyboard
- [ ] [P2] Drag and drop of sections, items into sections, items inside Custom sections, and teams; invalid drops refused — OST: absent (ref: CLH §5.3, chat.md §3; OST: absent)
- [ ] [P3] Start reordering (keyboard move buttons); Ctrl+Alt+Shift+Up/Down moves the item — OST: absent (ref: CLH §5.3, chat.md §3; OST: absent)
- [ ] [P2] Tree keyboard navigation — Teams: `role=tree`, focus follows selection after a delay, Ctrl+Enter pops out — OST: rows can't take focus and have only a TapHandler (ref: CLH §5.1; OST: ChatList.qml:359-362)
- [ ] [P2] Alt+Q collapse all sections — OST: absent (ref: CLH §6, chat.md §3; OST: Main.qml:45-87)
- [ ] [P3] Ctrl+L focus the list, Ctrl+F6 next section — OST: absent (ref: chat.md §23; OST: Main.qml:45-87)

---

## B. Conversation header

### B1. Layout and responsive
- [ ] [P2] Title width — Teams: fit-content, max 80 % without tabs — OST: capped at 35 % of the header (ref: CLH §7.2; OST: Conversation.qml:200)
- [ ] [P2] Breakpoints on the header's own width (ResizeObserver) — Teams: <640 tabs move under the title and become a dropdown, Meeting details goes into ···; <720 Participants goes into ···; ≥834 Meet now shows its text; context buttons 3/2/0 at ≥640/480–639/<480, the rest in a "Sidepane Features" group at the top of ··· — OST: fixed pixel offsets, and tabs that don't fit are made invisible (ref: CLH §7.3; OST: Conversation.qml:225-228, 279-319)
- [ ] [P3] Header background `colorNeutralBackground3` with a bottom border, and no border when collaborative tabs show — OST: surface colour with a hairline (close; check the colours) (ref: CLH §7.2; OST: Conversation.qml:158, 321)

### B2. Chat tabs
- [ ] [P1] Placeholder tabs — Teams: Notes, Recap and Storyline appear only under their rules (Recap: meetings with a recap, plus ad-hoc chats with `showRecapTabForAdhocChat` live on; Notes: flag-gated, internal, non-meeting; Storyline: 1:1 with Engage) and open working content — OST: every chat shows Notes/Recap/Storyline (self chat: Storyline), and they open "isn't available in OST yet" (ref: CLH §7.9; OST: Conversation.qml:50-51, 940-950)
- [ ] [P2] Chat's own tabs from `tabsConnection`, plus "+ Add a tab" and the tab menu (Copy link to tab, Remove) — OST: chats never load their added tabs; there's no Add-a-tab (ref: CLH §7.1, §7.9, chat.md §8; OST: Conversation.qml:43-51)
- [ ] [P2] Meeting chat tabs (Chat, Shared, Recap, Attendance, Q&A, Meeting Whiteboard, Transcript, Breakout Rooms, Speaker coach; not Notes) — OST: shows the generic chat tab set (ref: CLH §7.6; OST: Conversation.qml:51)
- [ ] [P2] Shared tab content — Teams: files, links and media in the chat, with an upload button (Attach cloud files / Upload from this device) and a Links folder — OST: built only from the 50 loaded messages; no upload (ref: chat.md §8; OST: Conversation.qml:854-929)
- [ ] [P3] Tab max width 15rem/7rem by experience width — OST: absent (ref: CLH §7.3; OST: Conversation.qml:222)

### B3. 1:1 chat
- [ ] [P1] Call control — Teams: one sticky primary button, **Audio call** or **Video call** (whichever was last used, saved to `mruChatHeaderCallOption`), plus a "More call options" chevron whose menu has Video call, Audio call, delegate items, Audio call ‹mobile›/‹work› — OST: an Audio call button, and a chevron whose menu has only "Audio call"; no way to start a video call (ref: CLH §7.4, chat.md §8; OST: Conversation.qml:279-298)
- [ ] [P2] Call control hidden when the user is blocked, it's a bot without calling, the thread is write-locked, or you're the only member — OST: shown for every non-self, non-channel chat (ref: CLH §7.4; OST: Conversation.qml:280, 287)
- [ ] [P2] Roster button — Teams: PeopleAdd "Start a group chat", which opens add-people — OST: "View participants" toggles a people popup (ref: CLH §7.4; OST: Conversation.qml:299-305)
- [ ] [P3] Alt+Shift+V video call — OST: only Alt+Shift+A exists (ref: chat.md §8/§23; OST: Main.qml:79)

### B4. Group chat
- [ ] [P1] Call control — Teams: **Meet now** (video icon; text at ≥834 px) plus a chevron whose menu has only "Audio call"; disabled above 20 members ("Calls aren't available in chats with more than 20 people"); Join / live roster while a call is on — OST: the same Audio call button as 1:1 (ref: CLH §7.5, chat.md §8; OST: Conversation.qml:279-298)
- [ ] [P1] Roster count button — Teams: bold member count, tooltip "View and add participants", popover listing members and Add people — OST: a people icon with no count; members are guessed from message senders, not the thread roster (ref: CLH §7.5, chat.md §7; OST: Conversation.qml:299-305, 1182-1192)
- [ ] [P2] Rename pencil "Name group chat" — Teams: popover with "Group name", 250-char and ':' errors, Save → `PUT {chatsvc}/v1/threads/{id}/properties?name=topic` — OST: absent (ref: CLH §7.5, chat.md §7; OST: absent)
- [ ] [P2] Add people with history options; remove a member (≥3) — OST: absent (ref: chat.md §7; OST: absent)
- [ ] [P3] Change the group picture — OST: absent (ref: chat.md §7; OST: absent)

### B5. Meeting chat
- [ ] [P1] **Join** (primary; hidden when cancelled, disabled while in the call) and **Meeting details** (≥640 inline, else in ···) — OST: shows the 1:1-style Audio call button (ref: CLH §7.6; OST: Conversation.qml:279-298, Main.qml:1677)
- [ ] [P3] Recurring icon beside the title — OST: absent (ref: CLH §7.6; OST: absent)

### B6. Channel header
- [ ] [P2] **Meet now** split button — Teams: "Meet now" text plus a chevron with Meet now / Schedule a meeting; disabled-reason tooltips; becomes "Schedule a meeting" when Meet now isn't allowed — OST: absent (ref: CLH §7.7, TC §22/§26; OST: Conversation.qml:279-305)
- [ ] [P2] Context area shows only on Posts — Teams: Find in channel and Channel details appear only while Posts is selected — OST: Find and details are always shown; a people-add button shows in channels too (ref: CLH §7.7, §7.8; OST: Conversation.qml:299-319)
- [ ] [P3] Show/Hide tab conversation button on Extension/Website tabs — OST: absent (ref: CLH §7.8, TC §20; OST: absent)
- [ ] [P3] Channel card on title hover; sensitivity label; Join channel — OST: absent (ref: CLH §7.7; OST: Conversation.qml:187-205)

### B7. Header ··· menus
- [ ] [P1] "More chat options" ··· — Teams: View Copilot history, Open in new window, Schedule meeting, Share screen, Mark as read/unread, Move to ▸ / Remove from section, Mute, [Manage notifications ▸], Copy link (`{origin}/l/chat/{id}/conversations?…`), Leave, Delete / "Remove chat history" — OST: absent (ref: CLH §7.4-7.6, chat.md §8; OST: Conversation.qml:279-319)
- [ ] [P2] "More channel options" ··· — Teams: See new posts at top/bottom, Open in new window, notifications, Move to, Show/Hide, Edit/Manage channel, Copy link, Get email address, Leave/Archive/Delete — OST: absent (ref: CLH §7.7, TC §12/§15; OST: absent)

### B8. Context area and banners
- [ ] [P2] Chat details pane — Teams: right pane with People (up to 7, presence, See all), Pinned messages (up to 10), Shared; labels "Open chat details" / "Close chat details", PanelRightExpand icon — OST: a 300 px popup listing message senders; static label; panel-left icon (ref: CLH §7.4, chat.md §9; OST: Conversation.qml:316-319, 1173-1221)
- [ ] [P2] Find in chat — Teams: right pane "Find in chat" with server search, results list, date/person filters — OST: inline bar matching only the loaded messages (partly done) (ref: CLH §7.4, chat.md §20; OST: Conversation.qml:771-837)
- [ ] [P2] Pinned-message banner under the header (newest pin; click jumps to it) — OST: absent (ref: chat.md §8/§9; OST: absent)
- [ ] [P3] Copilot and Agents-and-bots context buttons (licence) — OST: absent (ref: CLH §7.4; OST: absent)
- [ ] [P3] Out-of-office / status-message banner above the composer in 1:1 — OST: absent (ref: chat.md §8; OST: absent)

---

## C. Message timeline

### C1. Loading and message types
- [ ] [P1] Load older messages on scroll-up — Teams: pages back through history — OST: one page of the newest 50; no paging (ref: MC §1, chat.md §18; OST: backend.rs:968, src/api/messages.rs:89-133)
- [ ] [P1] Visible message types per chat kind (Contacts, Files, Media_Card, Media_Video, AudioMsg, UriObject, Poll, SmartCard, Embed, recordings, transcripts, …) — OST: keeps only Text/RichText* and ended Event/Call; everything else is dropped (ref: MC §1; OST: src/api/messages.rs:179-201)
- [ ] [P2] Adaptive Cards and other app/bot cards (schema ≤1.6, Hero/Thumbnail/List/Receipt/O365 connector cards) — OST: absent (ref: chat.md §18, MC §1; OST: src/api/messages.rs:199-201)
- [ ] [P2] Quoted-reply rendering — Teams: a quote block with the author and time; clicking it jumps to and highlights the original — OST: only sanitised generic `blockquote` HTML (ref: chat.md §18; OST: src/api/messages.rs:345-347)
- [ ] [P2] Forwarded-message rendering — Teams: "Forwarded" header with the original sender and a link to the original — OST: absent (ref: chat.md §18; OST: absent)
- [ ] [P2] De-duplication key `from + (clientMessageId || id)` and pending local echoes — OST: no local echo, so nothing to de-duplicate (ref: MC §1; OST: src/api/messages.rs:119-131)
- [ ] [P3] Synthetic rows: retention notice, "You won't see messages that were sent before you joined the chat." — OST: absent (ref: MC §1; OST: absent)
- [ ] [P3] Link previews (unfurl cards) — OST: absent (ref: chat.md §14; OST: absent)

### C2. Grouping and layout
- [ ] [P2] Group-break rules — Teams: also breaks on bot on-behalf-of, a different `appMetaData.id`, call recordings, shared messages, a missing arrival time, and (chats) a message with replies — OST: breaks only on sender, call rows, dividers and the 5-minute gap (ref: MC §2; OST: Conversation.qml:141-143)
- [ ] [P2] Bubble corner squaring — Teams: top = both bottom corners 0; center = all four 0; bottom = both top corners 0 — OST: squares only the inner side (left for others, right for own) (ref: MC §2/§3; OST: Conversation.qml:482-489)
- [ ] [P2] Max widths and side margins by message-pane container width (others calc(100%−70/142/198px), own calc(100%−66/142/160px); margins 16/24/40; avatar 32 at ≥480) — OST: min(640 px, 70 %) and a fixed 72 px side margin (ref: MC §3; OST: Conversation.qml:373, 456, 492)
- [ ] [P3] Own bubble dark-theme colour `#2B2B40`; bubble border `colorTransparentStroke` — OST: theme.brandTint, no border (check against Theme) (ref: MC §3; OST: Conversation.qml:490-491)
- [ ] [P3] Avatar hidden for admin- or spillage-deleted messages, in multiselect, and in lobby chats — OST: absent (ref: MC §2; OST: Conversation.qml:440-447)
- [ ] [P3] Message density Comfy/Compact; message font size setting — OST: absent (ref: chat.md §1/§18; OST: absent)

### C3. Timestamps, dividers, jump buttons
- [ ] [P2] Year format — Teams: older than this year = `d/m/yy` ("11/6/25 10:32 AM") — OST: 4-digit year ("11/6/2025") (ref: MC §4; OST: Conversation.qml:117, ChannelPosts.qml:377)
- [ ] [P2] Timestamp tooltip/aria — Teams: "Today at 10:32 AM", "Yesterday at …", "November 6, 2025 10:32 AM" — OST: absent (ref: MC §4; OST: Conversation.qml:448-457)
- [ ] [P2] "Last read" placement — Teams: shown whenever the horizon is non-zero (above the oldest newer message from someone else, or own if bookmarked); `role=heading` — OST: suppressed when that message is the oldest one loaded; no heading role (ref: MC §5; OST: Conversation.qml:136, 386-408)
- [ ] [P2] Floating buttons: "Jump to last read" (while the divider is off-screen), "Jump to newest", "New messages" pill with a count, "Recent" — OST: absent (Ctrl+J only jumps to newest) (ref: MC §5, chat.md §18; OST: Conversation.qml:39, Main.qml:63)
- [ ] [P3] Deep-linked message highlighted for 4 s — OST: absent (ref: MC §5; OST: absent)

### C4. Message states
- [ ] [P1] Optimistic send with Sending… / Retrying… and failure states ("Failed to send.", "Message didn't send…", red bubble) with Retry / Edit / Delete — OST: no local echo; on error a status-bar text, and the typed text is already cleared (ref: MC §6; OST: Conversation.qml:1242-1255, backend.rs:2727-2757)
- [ ] [P1] Delete → tombstone "This message has been deleted." with **Undo** (`DELETE …/messages/{id}?behavior=softDelete`; undo `DELETE …/properties?name=deletetime`), shown whenever `canBeUndeleted`, admin-deleted, has replies, etc. — OST: plain DELETE without `behavior=softDelete`; the tombstone shows only for messages deleted in this session; no Undo (ref: MC §6, §13, §21; OST: src/api/messages.rs:613-624, backend.rs:1038-1041, 1069-1072, 2523-2529)
- [ ] [P2] "Edited" in the details slot on every edited message, tooltip "Edited {{editTime}}" — OST: appended to the name/time line, so it disappears on grouped messages; no tooltip (ref: MC §6; OST: Conversation.qml:450-453)
- [ ] [P2] IMPORTANT / URGENT label (uppercase, red, icon) — OST: `importance` isn't parsed (ref: MC §6, chat.md §17; OST: src/api/messages.rs:135-255)
- [ ] [P3] Bot/card "Updated" state; "Delete failed" — OST: absent (ref: MC §6; OST: absent)
- [ ] [P3] Tombstone styling — Teams: muted text, margin 1.2rem — OST: italic secondary text inside the bubble (ref: MC §6; OST: Conversation.qml:532-541)

### C5. Read receipts
- [ ] [P1] Seen rule — Teams: seen = arrival ≤ **min** of the other members' horizons (and ≥ their messageVisibilityTime), evaluated only once every member has a horizon; "Seen by everyone" in groups — OST: uses the **max** horizon, so one reader marks a group message Seen (ref: MC §7; OST: src/api/messages.rs:685-704, 741-746)
- [ ] [P2] Enabled only for 2–20 members, `receiptsEnabledType ≠ None`, and the user preference on — OST: no member-count or preference check before drawing (ref: MC §7, chat.md §18; OST: Conversation.qml:709-716)
- [ ] [P2] "Sent" goes on the newest **Delivered** own message; tooltips Sent/Seen/Seen by everyone/Sending/Failed/Scheduled; icon 16 px at ≥480 — OST: newest own message regardless of status; no tooltip; 12 px (ref: MC §7; OST: Conversation.qml:150-155, 709-716)
- [ ] [P2] Live receipt updates via `ThreadActivity/MemberConsumptionHorizonUpdate` — OST: polls every 20 s while the newest own message is unseen (ref: MC §7; OST: Main.qml:1612-1620)

### C6. Typing indicator
- [ ] [P1] Receive timeout — Teams: `userTimeout` 22000 ms; cleared by Control/ClearTyping or a real message; stays 3 s after the list empties — OST: 6 s (ref: MC §8; OST: backend.rs:959, 2376-2384)
- [ ] [P1] Multiple typers — Teams: "X and Y are typing", "X, Y, and Z are typing", "X, Y, and N others are typing" — OST: one name only, the last one seen (ref: MC §8; OST: backend.rs:2373)
- [ ] [P2] Send throttle — Teams: leading edge, once per 20000 ms; not while editing, in reply chains, or when members are ≤1 or >20 — OST: every 3 s, also while editing (ref: MC §8; OST: backend.rs:961, 2597-2621, Conversation.qml:1363-1366)
- [ ] [P2] Placement and look — Teams: small text with an animated ellipsis (`data-tid="typing-indicator"`); avatar only for bots; hidden in channels and above 20 members — OST: avatar plus three dots over the compose edge, text only for screen readers; not hidden in channels (ref: MC §8; OST: Conversation.qml:723-752, backend.rs:2355-2359)
- [ ] [P3] Typing body `contenttype: "Application/Message"` — OST: sends `"text"` (ref: MC §8; OST: src/api/chat.rs:386-390)

### C7. System / control messages
- [ ] [P2] Control-message rows (AddMember with history variants, DeleteMember, TopicUpdate, PictureUpdate, MemberJoined/Left, pin/unpin, MemberRenamed, ShowChatHistory, ModalityUpdate, recording/transcript) with a bold clickable actor — OST: all dropped (ref: MC §9, chat.md §7; OST: src/api/messages.rs:199-201)
- [ ] [P2] Call rows — Teams: started rows ("Call started"/"Meeting started"); ended row = time + EM SPACE + text + NBSP + **bold** `{h}h {m}m {s}s`; missed = ended, not a meeting, <2 participants; not rendered without duration or participants; aria "Call ended at … after …" — OST: only ended rows; duration without hours, not bold; missed = duration 0 (ref: MC §9; OST: src/api/messages.rs:179-198, Conversation.qml:411-438)
- [ ] [P3] Meeting started card with Join, recording and transcript cards — OST: absent (ref: MC §9, chat.md §18; OST: absent)

### C8. Channel posts and replies
- [ ] [P1] Hover bar and ··· menu on posts and replies (react, Edit, Delete, Copy link, Follow, Pin, Save, Mark as unread, Open conversation in new window) — OST: only an add-reaction button under the post (ref: MC §11, §13, TC §14; OST: ChannelPosts.qml:124-189)
- [ ] [P2] Subject line on posts (h2, 18 px semibold) and "Add a subject" (250 chars) in the new-post compose — OST: subjects neither shown nor writable (ref: MC §10, §18, TC §15; OST: ChannelPosts.qml:84-122, Conversation.qml:1348)
- [ ] [P2] Reply summary — Teams: "Open {n} replies from {u1}, {u2} and {u3}[, and # others]" (no singular; "you"; bold when unread) — OST: shows the last 3 replies inline plus "N earlier replies" (ref: MC §10; OST: ChannelPosts.qml:73, 192-211)
- [ ] [P2] Collapsed reply box text — Teams (classic post layout): "Reply"; "Reply in thread" only in threaded channels; disabled text when replying is blocked — OST: "Reply in thread" on classic posts (ref: MC §10, §18; OST: ChannelPosts.qml:255, 283)
- [ ] [P2] Threads (ConvUX) layout channels — Teams: chat-like canvas, "N replies" link with replier avatars, "Last reply …", thread side pane with "Send to: thread only / thread and channel", Threads list pane — OST: every channel drawn as posts (ref: MC §10/§11, TC §14; OST: ChannelPosts.qml:1-379)
- [ ] [P2] See new posts at top/bottom (header ··· and Setting) — OST: always at the bottom (ref: TC §15, CLH §7.7; OST: ChannelPosts.qml:55-58)
- [ ] [P2] Channel reaction count shown only when >1 — OST: always shows the count (ref: MC §14; OST: ChannelPosts.qml:139-144)
- [ ] [P2] Files in channel posts go to the channel's SharePoint folder — OST: uploads to the sender's OneDrive chat-files folder (ref: TC §21; OST: src/api/files.rs:99-118, Conversation.qml:1243-1245)
- [ ] [P3] Announcements (headline, background, colour scheme), cross-post (Post in other channels), "Also notify via email", "Post" button — OST: absent; the new post uses the chat compose with a Send icon (ref: MC §10/§17/§18, TC §15; OST: Conversation.qml:1272, 1423-1430)
- [ ] [P3] Mention / importance / attachment icons after the summary; bold for unread replies — OST: absent (ref: MC §10; OST: absent)

---

## D. Message actions

### D1. Hover bar
- [ ] [P1] Quick reactions from the user preference `defaultMessageReactions` (live like, heart, laugh, surprised = **4**; legacy six while loading; "like" with the preferred skin tone) — OST: 5 hard-coded (like, heart, laugh, surprised, sad) (ref: MC §11, chat.md §19; OST: Conversation.qml:669)
- [ ] [P1] **More reactions** button (full picker; any emoji or custom emoji can be a reaction) — OST: absent in chats (ref: MC §11, chat.md §19; OST: Conversation.qml:668-682)
- [ ] [P1] **More options** (···) on every message — OST: only on own messages (ref: MC §11; OST: Conversation.qml:683-692)
- [ ] [P1] Contextual action on the bar — Teams: Edit on own messages, Reply with quote on others' (threaded variants per the action table) — OST: absent; Edit sits inside ··· (ref: MC §11; OST: Conversation.qml:694-705)
- [ ] [P2] Visibility rules — Teams: member, Delivered status, not pending/mid-move, no other popover, closes on scroll, 1500 ms safe zone — OST: shown on hover for every non-deleted, non-call row (ref: MC §11; OST: Conversation.qml:656-657)
- [ ] [P2] Reaction button state — Teams: `aria-pressed` underline when already reacted; at the 20-reaction limit the tooltip "You've reached the 20-reaction limit…" and the click is refused — OST: no pressed state, no limit (ref: MC §11; OST: Conversation.qml:670-680)
- [ ] [P2] Keyboard — Teams: focusing a message opens the bar; Enter goes to the first reaction, Esc closes; hidden "More message options" button — OST: messages can't take focus (ref: MC §11; OST: Conversation.qml:356-717)
- [ ] [P3] Customize reactions dialog (5 slots, skin tone, Save; `updateUserPreferences(defaultMessageReactions)`) — OST: absent (ref: MC §11, chat.md §19; OST: absent)

### D2. Right-click
- [ ] [P1] Right-click on a message opens the ··· menu at the pointer, with the reaction strip on top and the hover-bar actions kept — OST: absent (ref: MC §12, chat.md §19; OST: absent)
- [ ] [P1] Text selection and copy (native menu when text is selected; Ctrl+C) — OST: message bodies are plain `Text`, which can't be selected (ref: MC §12, chat.md §19; OST: Conversation.qml:524-546, ChannelPosts.qml:351-366)

### D3. ··· menu and its items
- [ ] [P1] Menu structure — Teams: core items in registry order (hover-bar actions removed when opened from the bar), divider, first 3 secondary items sorted by usage, Translation ▸ (chats), Report this message, More actions ▸ — OST: a Menu with Edit and Delete only (ref: MC §13; OST: Conversation.qml:694-705)
- [ ] [P1] **Reply with quote** (Q; quotes into the compose; Alt+Shift+R replies to the last message) — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P1] Edit rules and behaviour — Teams: own only; not Urgent, audio, Loop, or deeplink messages; no time limit; keeps formatting; Done/Cancel in place — OST: edits through the compose box with a strip; the PUT body is plain escaped text, so formatting, mentions and images are lost (ref: MC §13, §15, chat.md §19; OST: Conversation.qml:697-700, 755-766, src/api/messages.rs:589-610)
- [ ] [P2] **Forward** (dialog, note, ≤5 images; Multiple messages split; `POST …/messages/forward`) — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P2] **Copy link** (text "Copy link"; title "Copy message link"; "Copied to clipboard") — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P2] **Save this message** / Unsave (`PUT …/rcmetadata/{id}` `{s, mid}`) and the Saved view — OST: absent (ref: MC §13, chat.md §4/§19; OST: absent)
- [ ] [P2] **Pin for everyone** / Unpin (thread property; opens the info pane) — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P2] **Mark as unread** from a message (`markMessageAsUnread`; "Message marked as unread") — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P2] **Read by N of M** ▸ reader list (own message in group chats) — OST: absent (ref: MC §13, chat.md §18; OST: absent)
- [ ] [P2] Delete shows no confirmation (row becomes the tombstone); hidden for others' messages unless admin rules allow — OST: no confirmation (matches), but see C4 for soft delete and Undo (ref: MC §13; OST: Conversation.qml:701-704)
- [ ] [P3] Translation ▸ (Translate / See original, auto-translation, Never translate, Settings) — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P3] Share to Outlook, Immersive Reader, Report this message, More actions ▸ (app actions), Remind me (flag off), Follow thread (channel), Open conversation in new window — OST: absent (ref: MC §13, chat.md §19; OST: absent)
- [ ] [P3] Message keyboard shortcuts E, Del, P, S, U, F, T, R, Q, Ctrl+Alt+R, Shift+Up/Down multiselect — OST: absent (ref: MC §20, chat.md §23; OST: Main.qml:45-87)

### D4. Reactions under a message
- [ ] [P1] Every reaction key renders as its emoji — Teams: names from emoji metadata; skin tones (`-tone\d`) folded by `commonKey` — OST: any key other than the 6 legacy ones is drawn as 🙂 (ref: MC §14; OST: src/api/messages.rs:76-86, 284)
- [ ] [P2] Pill order — Teams: pills with your reaction first, by count descending — OST: server order (ref: MC §14; OST: src/api/messages.rs:267-290, Conversation.qml:626-650)
- [ ] [P2] Pill details — Teams: up to 3 skin-tone variants, count bold when it includes you, aria "{n} {name} reaction(s)." — OST: one emoji, count not bold (ref: MC §14; OST: Conversation.qml:628-649)
- [ ] [P2] Overflow "+N" (N = hidden **people**), 5 slots in chat (3 below 480 px), "More reactions" hover menu — OST: absent (ref: MC §14; OST: Conversation.qml:620-651)
- [ ] [P2] Who reacted — Teams: hover list (300 ms) with avatar, name and emoji, newest first; clicking a row opens a 1:1; Delete on your own row; paged via `GET v1/threads/{conv}/messages/{id}/annotations` — OST: absent (ref: MC §14, chat.md §18; OST: absent)
- [ ] [P2] Add-reaction button after the pills in chats (`enableMultipleReactionsPerUser`) — OST: absent in chats; channel posts have one with 6 fixed emoji (ref: MC §14; OST: ChannelPosts.qml:152-188)
- [ ] [P2] Limits — Teams: 20 distinct reactions per user; a new skin tone replaces the old; HTTP 413/400 banner "Current message size limit reached…"; `canReact` false in archived teams — OST: absent (ref: MC §14; OST: src/api/messages.rs:556-586)
- [ ] [P3] Reaction toggle is optimistic — OST: waits for the PUT, then reloads the whole timeline (ref: MC §14; OST: backend.rs:2561-2581)

---

## E. Composer

### E1. Layout and toolbar
- [ ] [P2] Single-line vs multiline — Teams: one line with a side toolbar; switches to a bottom toolbar when formatting is open, files/cards are attached, or the text wraps — OST: one layout with tools always at the bottom right (ref: MC §15; OST: Conversation.qml:1270-1432)
- [ ] [P2] Toolbar items and labels — Teams: "Show/Hide Formatting options (Ctrl+Shift+X)", "Emoji, GIFs and Stickers", "Attach files (Alt+Shift+O)", [Write with Copilot], Loop, "Actions and apps", Send / Done + Cancel while editing — OST: Format, Emoji, Attach files, Actions and apps, divider, Send; labels differ, no tooltips, no Done/Cancel, no Loop (ref: MC §15; OST: Conversation.qml:1381-1431)
- [ ] [P2] Ctrl+Shift+X toggles formatting — OST: absent (ref: MC §15/§20, chat.md §10; OST: Conversation.qml:1355-1361)
- [ ] [P2] Placeholders — Teams: "Type a message" (bot), "Type a message to this group." / "Type a message to {{name}}." (private chats), "Reply in thread", else "Type a message" — OST: "Type a message" / "Start a post" (ref: MC §18; OST: Conversation.qml:1348)
- [ ] [P3] Loop components button and "Make this collaborative" — OST: absent (ref: MC §15, chat.md §15; OST: absent)

### E2. Formatting bar
- [ ] [P2] Full group set — Teams: B/I/U/S · lists · highlight, font colour, font size · quote, link, code block · rich style, inline code, clear formatting · indent · horizontal rule · table ops · undo/redo · [Cancel] — OST: B/I/U/S and the two lists only (ref: MC §16, chat.md §11; OST: Conversation.qml:1278-1302)
- [ ] [P2] Overflow into "More options" taken from the end — OST: absent (ref: MC §16; OST: Conversation.qml:1278)
- [ ] [P2] Formatting toggles and caret formatting — Teams: Ctrl+B with no selection sets the style for the next text; pressing again removes it — OST: `wrapSelection` does nothing without a selection and nests tags when reapplied (ref: MC §16/§20; OST: Conversation.qml:1225-1234)
- [ ] [P2] Shortcuts Ctrl+K link, Ctrl+Shift+C inline code, Ctrl+Shift+B code block, Ctrl+Alt+4 quote, Ctrl+Alt+1/2/3/P headings — OST: only Ctrl+B/I/U and Ctrl+Alt+X (ref: MC §20, chat.md §11/§12; OST: Conversation.qml:1355-1361)
- [ ] [P2] Live Markdown autoformat (`*bold*`, `_italic_`, `` ` ``, ```` ``` ````, `#`, `>`, `1.`, `-`) — OST: absent (ref: chat.md §11; OST: absent)
- [ ] [P3] Code block language dropdown, line numbers, Wrap text — OST: absent (ref: chat.md §12; OST: absent)

### E3. Emoji / fun picker
- [ ] [P2] Unified fun picker — Teams: tabs All | Emoji | GIFs | Stickers (policy-gated); search "Find something fun"; "GIFs powered by GIPHY" — OST: emoji only, search "Search emoji" (ref: MC §17, chat.md §13; OST: EmojiPicker.qml:6-149)
- [ ] [P2] Emoji set and categories — Teams: its personal-expressions metadata; categories Recent, Smilies, Hand gestures, People, Animals, Food, Travel and places, Objects, Activities, Symbols, Custom — OST: a hard-coded ~350-emoji subset in 8 categories (no Hand gestures; "Travel") (ref: MC §14, chat.md §13; OST: EmojiPicker.qml:16-64)
- [ ] [P2] Recent emoji roam (`recentReactions`) — OST: in-memory only, lost on restart (ref: MC §14, chat.md §13; OST: EmojiPicker.qml:12, 69-72)
- [ ] [P3] Skin tones (right-click, 6 tones), 1500 ms emoji tooltips, custom org emoji — OST: absent (ref: MC §14, chat.md §13; OST: absent)
- [ ] [P3] `:shortcode` autocomplete — OST: absent (ref: chat.md §13; OST: absent)

### E4. "+" flyout and Attach
- [ ] [P2] "+" Actions and apps items — Teams: Schedule message, Set delivery options, Record video clip, Schedule meeting, [Meet Now in channel replies], [Change permissions, Post in other channels for new posts], then installed apps — OST: "Upload from this device" and "Emoji" (ref: MC §17, chat.md §10; OST: Conversation.qml:1415-1420)
- [ ] [P2] Attach menu — Teams: "Search cloud files", "Recent cloud files", "Attach cloud files", "Browse Teams and Channels", "Upload from this device"; disabled offline — OST: opens the OS file dialog directly (ref: MC §17, chat.md §14; OST: Conversation.qml:1262-1267, 1402-1408)
- [ ] [P2] Paste or drop images and files into the compose (inline hosted images) — OST: absent (ref: chat.md §14; OST: Conversation.qml:1344-1380)
- [ ] [P3] Upload progress in the chip and background upload — OST: a status-bar line "Uploading …" (ref: chat.md §14; OST: backend.rs:4195-4197)
- [ ] [P3] Permission check banner "Give access" on file chips — OST: absent (ref: chat.md §14; OST: absent)

### E5. Delivery options, schedule send, Enter, limits
- [ ] [P2] Set delivery options — Standard / Important (Ctrl+Shift+I, "Important!") / Urgent (disabled above 20 members, not in channels) — OST: absent (ref: MC §18, chat.md §17; OST: absent)
- [ ] [P2] Enter rule — Teams: plain Enter sends only when the setting is Default **and** the formatting bar is collapsed; Ctrl+Enter always sends — OST: Enter sends even with the formatting bar open (ref: MC §18, chat.md §10; OST: Conversation.qml:1370-1375)
- [ ] [P2] Hint under a non-empty compose — Teams: "**Shift+Enter** starts a new line." / "**Enter** starts a new line." (the key links to Settings; not on a new channel post) — OST: absent (ref: MC §18; OST: absent)
- [ ] [P3] Enter setting roams as `composeUserSettings.enterKeyBehavior` — OST: local settings file (ref: MC §18, chat.md §10; OST: Conversation.qml:1362, 1369, backend.rs:3137-3167)
- [ ] [P3] Schedule send (right-click Send, "+" › Schedule message, 30-min slots, 120 days, "Scheduled" state) — OST: absent (ref: MC §18, chat.md §17; OST: absent)
- [ ] [P3] Pre-send checks and limits — "Please type a message to continue.", "Message is too large to send." (90112 bytes), editor/paste limits — OST: empty input silently ignored; no size check (ref: MC §18, chat.md §10; OST: Conversation.qml:1242-1255)

### E6. Drafts
- [ ] [P2] Roamed drafts — Teams: `SaveMessageDraft` debounced 400 ms, REST `v1/users/ME/drafts`, `SetConversationHasDraft` — OST: local JSON file, 1000 ms debounce, plain text only (formatting lost) (ref: MC §18, chat.md §10; OST: Conversation.qml:85-89, backend.rs:1323-1354, 2978-3003)
- [ ] [P3] "Discard" with confirmation (trash in the expanded compose) — OST: absent (ref: MC §18, chat.md §10; OST: absent)
- [ ] [P3] Channel "Continue your draft" — OST: absent (ref: MC §18; OST: absent)

### E7. @mentions
- [ ] [P1] @ picker in compose — Teams: `SearchMentionsV3` (users, tags, channels/teams, apps), debounced 200 ms; inserts a mention entity (`schema.skype.com/Mention` span + `properties.mentions`) — OST: absent; typed "@" is plain text (ref: MC §19, chat.md §17; OST: absent)
- [ ] [P2] @Everyone (group ≤250, meeting ≤1000; banner over 50 people), @channel/@team, tags ("Channel tag | # people"), "(You)" / "(External)" suffixes, "Add someone to the chat", "Share someone's contact info" — OST: absent (ref: MC §19, chat.md §14/§17, TC §17/§18; OST: absent)

### E8. Other compose features
- [ ] [P3] Slash commands (/mute, /hide, /goto, /call, /meetnow, …) — OST: absent (ref: chat.md §15; OST: absent)
- [ ] [P3] Suggested replies chips — OST: absent (ref: chat.md §10; OST: absent)
- [ ] [P3] Record video/audio clip (Alt+Shift+E) — OST: absent (ref: MC §17/§20, chat.md §14; OST: absent)
- [ ] [P3] Spell check underline and suggestions — OST: absent (ref: chat.md §10; OST: Conversation.qml:1344-1354)

---

## F. Build plan (in dependency order)

1. **Conversation and roster model (foundation).** Fetch thread metadata and members (`GET {chatsvc}/v1/threads/{id}?view=msnp24Equivalent`: members, roles, topic, creator, chat type) and expose members, member count, and the meeting/bot/self type to QML. Many rules need it: the header roster count (B4), Meet now vs Audio vs Join (B3–B5), Leave/Delete rules (A9), receipts for 2–20 members and the min-horizon Seen rule (C5), the typing limits (C6), Urgent and @Everyone limits (E5/E7). Low protocol risk: the chat service is already used.
2. **Timeline data layer.** Page backward through history (`…/messages?…` with the reply's backward link or `syncState`). Parse every visible message type, `importance`, control messages, quotes, forwards and cards. Add local echoes with a pending/failed state. Switch delete to `?behavior=softDelete` and add undo (`DELETE …/properties?name=deletetime`). Map reaction keys from the personal-expressions metadata (`{statics}/evergreen-assets/personal-expressions/v1/metadata/{ver}/{locale}.json`). Unblocks C1–C4, C7 and D4. Research needed: the paging link shape, and the emoticon metadata URL/version.
3. **Message action framework.** Build one action registry that feeds the hover bar, the ··· menu and the right-click menu (MC §11–13), and make message text selectable. Then the actions, one at a time: Reply with quote (research the quote HTML Teams sends), Copy link (deep-link format), Mark as unread (consumption horizon plus bookmark), Save (`PUT …/rcmetadata/{id}`), Pin (`setPinnedItemsThreadProperty`: research the thread property), Forward (`POST …/messages/forward`: research the body), Read by (consumption horizons). Who-reacted uses `GET v1/threads/{conv}/messages/{id}/annotations`. Channel posts reuse the same framework (C8).
4. **Compose editor upgrade.** Mention entities, quote blocks, code, links and caret formatting all need a structured editor model, not tag-wrapping. Edit must send that HTML (not plain text). After that: the @ picker (`SearchMentionsV3`, a substrate search service that needs research; start with Graph people via the existing `search_people`), the full formatting bar, delivery options (`importance` on send), roamed drafts (`v1/users/ME/drafts`: research the body), and the Enter/hint rules. GIFs need Giphy research. Schedule send needs research (scheduled-message service).
5. **Conversation folders.** Sections, Favorites, Move to / Remove from section, hidden channels, the Meeting/Muted chats sections, collapse state, ordering and "See more" all come from `{csa}/api/v1/teams/users/me/conversationFolders` (GET/POST/PUT/PATCH/DELETE, `supportsAdditionalSystemGeneratedFolders`, `supportsSliceItems`). This is the main protocol-research item: record the request and response shapes from winpc. It unblocks A6, A7, A9 (Move to), A12 and the channel unread display (with the unread ids already fetched).
6. **Chat-item and header menus.** Mark read/unread (horizon, done in step 3). Mute, Hide, Delete chat, Leave (thread member DELETE) and Block need endpoint research: the CLH §7.10 TODO lists "worker endpoints for mute, pin, hide, delete, leave". Rename uses the known `PUT {chatsvc}/v1/threads/{id}/properties?name=topic`. Mark all as read should move to the worker's `markAllAsReadByAppName` workflow (CLH §2.1 TODO: its service calls).
7. **Header call control.** Sticky Audio/Video in 1:1 (video outgoing in the existing calling stack; MRU saved via `updateUserPreferences(userPersonalSettings)`: research the user-preferences endpoint, which also serves `defaultMessageReactions` and `composeUserSettings`). Group "Meet now" reuses `start_group_call`; meeting "Join" reuses `join_meeting`; channel Meet now / Schedule needs the channel meeting flow.
8. **Responsive header and list.** Header breakpoints on its own width, the tab dropdown, context-button overflow, list width breakpoints and the drag divider, the pill overflow row. Pure UI with no protocol work. Do it after the menus exist, so the overflow menus have content.
9. **Later / gated.** Threads (ConvUX) channel layout, announcements and cross-post, translation (middle tier `POST chats/{id}/messages/languages/{lang}`), Share to Outlook, Loop, Copilot, communities, pop-out windows.
