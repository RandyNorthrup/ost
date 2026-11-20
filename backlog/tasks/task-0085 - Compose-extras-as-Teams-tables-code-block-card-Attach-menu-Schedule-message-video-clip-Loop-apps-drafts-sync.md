---
id: TASK-0085
title: >-
  Compose extras as Teams: tables, code block card, Attach menu, Schedule
  message, video clip, Loop, apps, drafts sync
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T23:01:00Z'
updated_date: '2026-11-20T21:31:00Z'
labels:
  - desktop
  - messages
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0044 left of Teams' compose box (docs/spec/messages-and-composer.md §15): the formatting bar's tables (insert, rows, columns, delete), the code block card's ··· menu and syntax colours, the Attach menu (cloud files, browse channels), Schedule message, Record video clip, Loop components, installed apps' actions in +, drafts synced with Teams, and Teams' pre-send checks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tables can be inserted and edited from the formatting bar and are sent and shown as Teams does
- [x] #2 Code blocks show Teams' card menu and syntax colours
- [x] #3 Attach offers Teams' menu (OneDrive / cloud files, browse channels, upload) and sends what it picks as Teams does
- [x] #4 Drafts sync with Teams, and Teams' pre-send checks run
- [ ] #5 Verified side by side with Teams on winpc
- [x] #6 Schedule message and Record video clip work as in Teams
- [ ] #7 Loop components and installed apps' compose actions work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10: code blocks as Teams' compose: highlight.js-style colours in Teams' 5 classes (measured), Auto-detect language (on by default; Rust snippet detected, short line stays Plain Text, as Teams), the ··· menu (Display option ▸ Auto-detect language), header colours. Received cards already matched (Teams shows no colours there). "Make this collaborative" needs Loop (AC4).

- Drafts (AC5): Teams' roaming API is chatsvc v1/users/ME/drafts (POST, PUT {id}, DELETE), behind enableRoamMessageDraft. On this tenant Teams made no drafts calls while a draft was typed and the channel left, so drafts stay local there, as OST's do. The roaming body is still to be captured where the flag is on.
- Pre-send checks: Enter on spaces does nothing (as OST); too-large is done; the rest belong to unbuilt features (Loop, video, schedule).

- Schedule message: built and verified against Teams. Covers the + item, popover, compose header with Cancel scheduled time, POST/GET/DELETE v1/users/ME/drafts, and the pending bubble with Delete. OST TEST 91/92 were scheduled from OST and cancelled; OST TEST 90 was scheduled from Teams and cancelled. Left: editing a scheduled message (PUT drafts/{id}, not captured yet), Record video clip, Loop, and the installed apps in +.

- Editing a scheduled message: PUT drafts/{id} (captured from Teams with OST TEST 93), with an inline edit box headed "Select Done to deliver on …". Verified OST TEST 94: scheduled, edited (text and time), cancelled.

- Teams' chat list (2026-11-10) shows Quick views ▸ Drafts even when empty: "You have no draft messages." with an illustration, and Channels/Chats chips. A draft row is: avatar 32, chat name 14/600, "You: {draft}" 14 italic, and a ··· menu with Discard, Go to conversation and Open in new window. OST lists Drafts only while drafts exist. Whether scheduled messages appear there is unverified. A "Copilot" row now sits above Quick views (TASK-0038).

- Tables (AC1), 2026-11-12: researched on winpc ("OST TEST 111" from Teams): grid 7x5 picker, Insert column or row / Delete submenus, wire `<p>&nbsp;</p><table><tbody><tr><td><p>…` and received look. Qt 6.11's QQuickTextEdit takes QTextTable fine (the old frame crash didn't reproduce). Built: richtext.cpp table ops/export/state (nextCell/prevCell), FormatBar grid + menus, Enter/Tab in cells, send path, received styling (min 1 device px borders). Verified with --table-test [--table-send]: "OST TEST 112" stored identically to Teams' table; an earlier attempt sent flat "OST TEST 112bc123" before the send-path fix (left in OST group test).
- "Allow edits" (Loop table) waits for Loop (AC4).

- Attach (AC3) researched 2026-11-12: popover measured, FilePicker.aspx parameters captured (spec §17). Teams' Attach of ost-share-test.txt did nothing during the SharePoint 503s, so the attached-file chip and message format are still to capture before building.

- Attach (AC3) captured 2026-11-13 ("OST TEST 117", OST group test):
  - The popover asks substrate `search/api/v1/recommendations` (Scenario teamsDesktop.AttachFile, the last 3 messages as context) and searches with `suggestions?scenario=slimpicker.compose` (EntityType File, Size 25). Both are empty for ost-test1, so result rows are unmeasured. The empty states are measured: no recent files, and "We couldn't find any results" with Upload / Attach buttons.
  - A channel adds "Browse Teams and Channels": the same FilePicker.aspx, entered at the channel's folder (entry.sharePoint.byPath).
  - Picker: a 972.8 x 557.6 dialog (76% x 82%). Rail 68 (expands to 210 as an overlay); Home (Name with location, Opened, Owner, Activity); My files (Name, Modified, Modified By, Activity; 59 px rows; selected #CFE4FA); footer "{n} selected ✕", Attach and Cancel.
  - The compose card is 320 x 237.3: a #FAFAFA header (32 px icon, name 14/600, the default link's description from `driveItem/commands`, Remove attachment) over a c960x540 thumbnail.
  - Send: members via users/fetch; SP v2.0 `driveItem/invite` {recipients:[{email}], roles:["write"]}; then the message. Its files[] entry has state "reference", chicletBreadcrumbs from the site URL's segments, the default link as shareUrl/shareId, and permissionScope "Anyone". A "You've shared {name}" toast follows.

- Attach (AC3) built 2026-11-13:
  - AttachMenu.qml (the popover, its suggestions and search) and CloudPicker.qml (Home, My files and folders, Shared, Favorites, People, Meetings, Media, Quick access, More places, the Navigation Pane, selection and Attach).
  - The compose card in ComposeBox.
  - src/api/cloud_attach.rs: the shares and commands reads, the invite with Teams' prefer getDefaultLink header, and the record.
  - Verified on linuxlt with --attach-test [--attach-channel] [--attach-send]. OST TEST 119 (chat) and OST TEST 121 (channel) store records identical to Teams' 120 and 118, and Teams on winpc draws them the same.
  - The rest is in TASK-0130 (command bar, People's collaborators, Media headings, Link settings, suggestion rows, PostThread). Teams' received file card is TASK-0129.

- 2026-11-14: Record video clip is now TASK-0136 (native recorder; recording, review, compose card and send done and verified). Received clips are TASK-0135. AC4 still waits on the rest of 0136, Loop components and the installed apps' actions in "+".

- 2026-11-15: drafts roaming (enableRoamMessageDraft) is off by default in every Teams cloud config and only Microsoft's ECS rollout turns it on; no tenant setting exists. To get it early, ost-test1 and ost-test2 are now on Teams Public Preview (update policy "OST test accounts") and Microsoft 365 Targeted release (select users). Re-check ECS for enableRoamMessageDraft before capturing the roaming body. Teams' compose now shows "Write with Copilot" and "Loop components" for ost-test1.

- 2026-11-16 audit: AC4 split. Schedule message (scheduled messages work) and Record video clip (TASK-0135/0136) are done and checked as #6. Loop components and installed apps' compose actions are not built (#7).

- 2026-11-16 (subagent, c854fa1, merged):
  - Drafts follow Teams' protocol: kept on the device, and roamed to v1/users/ME/drafts (RegularDraft) only when Teams' enableRoamMessageDraft is on, with Teams' conflict banner and Saved draft dialog. The setting is off for ost-test1 (Teams on winpc sends no drafts and ignores server drafts), so OST, like Teams, keeps drafts on the device here. The roaming was checked OST-to-OST via the server (OST_ROAM_DRAFTS=1). Teams-to-OST sync can only be checked once Microsoft turns the setting on.
  - Pre-send checks: Teams' 16 checks measured from its code; the ones for chats and posts are built with Teams' wording and banner (empty or spaces, upload running, missing headline, over 90112 bytes, past schedule time, old video clip, bot mention in a reply). The empty-message banner was compared on winpc. The rest is in TASK-0203.

- 2026-11-20 (chat agent), measured on winpc (OST group test):
  - Loop components (the toolbar's 5th, data-tid popup-semo) puts Loop's paragraph in the box at once: a white radius-12 card (box width - 33.3, 16.7 in, 20.5 under the text; 48 header + 320 frame). Teams makes it at once: `{OneDrive}/_api/v2.1/drives/{d}/items/root:%2FMicrosoft%20Teams%20Chat%20Files/Loop%20paragraph.loop:/opStream/snapshots/snapshot` (no share link), then createLink {type edit, scope organization}. The header reads "Loop paragraph | People in your organization with the link can edit", with a trash Discard ("Discard draft message" / "The Loop component will be deleted.", Close / Discard; DELETE graph drives/{d}/items/{i}).
  - Send ("OST TEST 85 loop component from Teams"): content `<p>text</p> \n        <span itemtype="http://schema.skype.com/FluidEmbedCard" itemid="{uuid}"></span>`, cards [{appId FluidEmbedCard, cardClientId, contentType application/vnd.microsoft.card.fluidEmbedCard, content {componentUrl: the createLink webUrl + ?nav=…, sourceType Compose}}]; then PATCH graph item ?@microsoft.graph.conflictBehavior=rename {name: "{title}.loop"}.
  - Received: a 616.7 card in a 648 bubble; the header has the file name and Shared locations / Copy component / See who has access; frame 320 (messaging.fluid viewProperties growHeight, maxHeight 20rem).
  - "+" lists installed apps with compose commands (Polly, Workflows, Polls, Clipchamp, Power BI, Praise, Updates, Viva Learning; most recent first), then "Add a new app" store suggestions with Add, and a Get more apps footer; 340 x 480, scrolling. Polls/Polly: composeExtension/fetchTask → task module. Praise/Clipchamp: static taskInfo pages. Power BI: query panel ("Search here", initialRun; Unauthorized here → "Unable to reach app. Please try again."). Workflows/Updates: fetchCommands.
- Built, not yet verified: LoopCard.qml (compose + message), Kind::Compose/Message in loop_page, compose_target/compose_link/discard/rename, outbox LoopEmbed, `--loop-compose-test`; api::compose_apps + ComposeAppPanel + task module launch/submitAction, the "+" apps list and Get more apps.

- 2026-11-20 (chat agent), verified live (linuxlt, ost-test1, `--loop-compose-test`):
  - Loop components: OST's toolbar shows it (messaging.fluid allows compose); the button puts Loop's paragraph in the box (Loop's own container: "Add a title", the insert row Table / Bulleted list / Checklist / Task list / …); Loop made `Microsoft Teams Chat Files/Loop paragraph.loop` and OST gave it the organization edit link through SharePoint's v2.1 createLink ("People in your organization with the link can edit").
  - Discard: Teams' dialog, then the file is deleted (`--loop-compose-discard`).
  - Send: "OST TEST 85 loop from OST" went with Teams' exact FluidEmbedCard span and card (componentUrl = link + nav, sourceType Compose). Teams on winpc draws it exactly as its own: the "Loop paragraph" header with Shared locations / Copy component / See who has access, and the text OST typed into the component ("OST TEST 85 loop OST", "Loop body typed in OST"). OST draws the received component in Loop's frame under the same header.
  - Left: the title watch (Loop's page container gives no ComponentTitle events here, so a sent component keeps "Loop paragraph" unless it has a title Teams would rename it to; OST renames only when Loop reports one); the card's link description doesn't open link settings yet; a Loop component isn't kept in a chat's draft when you switch chats (it stays in your chat files).
  - Test messages: "OST TEST 85 loop component from Teams" (Teams), "OST TEST 85 loop from OST" (OST), and an empty "<h1>" message from a slip while measuring, all in OST group test, to delete; their .loop files are in ost-test1's Microsoft Teams Chat Files.
- Installed apps in "+": built (api::compose_apps installed apps with compose commands, the list under Teams' items with recency, Get more apps, ComposeAppPanel for search commands, task modules for fetchTask / taskInfo actions, submitAction, a picked result as Teams' InputExtension card); `--compose-apps-test` added; not yet run live.

- 2026-11-20 later: installed apps verified live with `--compose-apps-test`: "+" lists Clipchamp, Praise, Workflows, Updates, Polly, Viva Learning, Power BI and Polls (Power Automate Actions, with no compose command, left out as Teams does); Polls' action asked composeExtension/fetchTask and opened Microsoft Forms' page in Teams' task module (framed, initialize, success; closed without posting); Power BI's search panel asked composeExtension/query and showed Teams' "Unable to reach app. Please try again." for the bot's 502. Not yet compared side by side on winpc: the rows' icons and the order before anything is used (Teams keeps its own recent order). Test messages OST TEST 85 (Teams' and OST's) and the stray empty message were deleted from OST group test; the .loop files stay in ost-test1's Microsoft Teams Chat Files.

- 2026-11-20 (chatB), measured on winpc:
  - "+" in OST group test now: Teams' items, then installed apps Clipchamp, Praise, Workflows, Polly, Power BI, Polls, Updates, Viva Learning. Teams' order (shared worker `sortExtensibilityAppPickerCategory`): the recent section sorts ["MRU", "Alphabetical"]; MRU is the middle tier's `GET beta/users/apps/usage` appsMru (lastUsedTimeStamp, newest first) — so before first use apps are alphabetical, and usage is shared with Teams (POST beta/users/apps/usage).
  - "Add a new app" = the "suggested" section: store apps (collection app:co:all) with compose commands that you haven't installed, sorted AISuggested/TenantAppRanking/Alphabetical (alphabetical here), 10 rows: 36 px round icon (#FAFAFA) at 26, name 14/600 at 74 (+ a 16 px #616161 "Agent" mark 4 after for agents), description 12 #616161 (194.8 wide, ellipsis), Add (39.2 x 24, white, radius 4, 12 px) at 280.8, the rating (16 px star: #C7C7C7 outline "No ratings yet", or #5B5FC7 filled with "4.9" 12/700 + " (318 ratings)"), Privacy | Terms of use | Permissions 10/14 #424242 with #D1D1D1 bars; rows 90 apart; heading "Add a new app" 14 #424242 centred between lines.
  - Loop link settings: the description opens SharePoint's sharedialog.aspx Link settings (Teams embeds it) with only "People in {tenant}", "People currently in this chat" and "Only people with existing access", the file name ("Loop paragraph 1.loop") under the title; Apply = ShareLink {createLink, linkKind 3/scope 1…}; the header then reads "People currently in this chat with the link can edit" / "People in Secure Coast Network Solutions with the link can edit".
  - Drafts: Teams does NOT keep a box that holds a Loop component: switching chats drops the whole draft (text too, typed for real over VNC, three tries); the .loop file stays. A text-only draft is kept.
  - Rename: a component without a title is named after the chat: "OST group test Loop paragraph" (Teams' message "OST TEST 85 loop without title"), as fluid compose 997266 `lt` reads ComponentWithTitle.getTitleText(), else "{chat title} {kind name}".

- 2026-11-20 (chatB), built and checked live on linuxlt as ost-test1:
  - Rename after the title as Teams: at send OST reads the component's title through Loop's ComponentWithTitle.getTitleText() (loop_host.js titleText) and names the file "{title}.loop", else "{chat} Loop paragraph.loop" (api::loop_page::compose_file_name, ODSP's rules, unit-tested). OST's "OST TEST 85 loop from OST" (untitled) became "OST group test Loop paragraph 1.loop", as Teams' own untitled one became "OST group test Loop paragraph.loop".
  - Link settings: the description opens the share dialog's Link settings on the component's file ("Loop paragraph 6.loop") with Teams' three choices (Anyone and People you choose hidden); People currently in this chat made a new link (ShareLink with the chat's people), the component's link became it (nav kept), the old link was deleted, and the header read "People currently in this chat with the link can edit" (`--loop-compose-link`).
  - Drafts: as Teams, leaving the chat with a Loop component in the box drops the draft (`--loop-compose-switch`: no loop, no draft after coming back).
  - "+" menu: installed apps (yours and the conversation's) in Teams' MRU-then-name order from the middle tier's apps usage, which OST now also records when you use an app; "Add a new app" from the Store catalog (10, by name, ratings and agent marks, Add / Privacy / Terms of use / Permissions).
<!-- SECTION:NOTES:END -->
