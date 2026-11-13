---
id: TASK-0085
title: >-
  Compose extras as Teams: tables, code block card, Attach menu, Schedule
  message, video clip, Loop, apps, drafts sync
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T23:01:00Z'
updated_date: '2026-11-13T21:54:00Z'
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
- [ ] #4 Schedule message, Record video clip, Loop components and installed apps' actions work as in Teams
- [ ] #5 Drafts sync with Teams, and Teams' pre-send checks run
- [ ] #6 Verified side by side with Teams on winpc
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
<!-- SECTION:NOTES:END -->
