---
id: TASK-0085
title: >-
  Compose extras as Teams: tables, code block card, Attach menu, Schedule
  message, video clip, Loop, apps, drafts sync
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T23:01:00Z'
updated_date: '2026-11-20T16:15:00Z'
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
<!-- SECTION:NOTES:END -->
