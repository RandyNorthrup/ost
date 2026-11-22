---
id: TASK-0244
title: Second-account extras and delegation mention pills as Teams
status: To Do
assignee: []
created_date: '2026-11-22T18:26:00Z'
updated_date: '2026-11-22T20:44:00Z'
labels:
  - desktop
  - settings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0078 and TASK-0242: Teams' app bar gets 'Activity in other accounts and orgs' (its window not yet measured); Intelligent call delegation's Custom instructions show @mentions as Teams' pills (OST shows @Name text); the custom-hours layout wasn't compared with Teams.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With a second account, the app bar's 'Activity in other accounts and orgs' opens what Teams opens
- [ ] #2 Custom instructions show @mentions as Teams' pills, and the custom-hours layout matches Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-22 (agent setJ) measured on winpc (Teams 26304.1207, ost-test1; OST Test 2 signed in as a second account by VNC, "No, this app only", then signed out; call delegation turned on and off again, Inactive; follow-up hours switched to custom and back to work hours; nothing saved in Custom instructions):
  - App bar: the hub is Teams' MTMA hub v2 (enableMtmaHubV2): a 52 x 48 tile at the bar's bottom (radius 8, PersonAlert 24 #616161; hovered/open: filled brand on white), a #D13438 count (10/14 600) at 26, 0. It opens a 380-wide flyout beside the bar, bottom on the tile's, ~0.7 of the window tall: title 14/600 (16 in, a #E0E0E0 rule at 56.7); Unread / Channels / Chats pills (24 tall, 12 px, #D1D1D1 hairline; picked: #4F52B2, white) and Filter (24 x 23.3) at 73.3; then per other account an accordion: chevron 14, 32 px picture with its count, name 14/600, address 12/20, Account settings ··· (an org row 240 wide → Switch / Pin this org); entries (pad 8; 6 px dot column, picture 32 at 22, text at 62, time right): unread activity (bold, dot, a white 18 px disc with the kind's 16 px icon) and recent chats (meeting = calendar on #C5CBFA, "You: …" previews 2 lines), newest first; a missed call has Call / Chat (65 x 24); footer "Scroll to see more" (12/20 #4F52B2 + arrow) under a rule while more is below. Filter by: Mentions, Tag mentions, Followed threads, Orgs ›. Picking an entry switches to that account at it.
  - Custom instructions' people: an uneditable inline span (data-chip-*): 23.33 tall, margin 0 2, padding 1 8 1 4, 0.67 #E0E0E0 border, radius 4, #F5F5F5, gap 2, 16 px Call icon (#5B5FC7, colorBrandForeground1) for a transfer target or ContactCard (#341A51, colorPalettePurpleForeground2) for a contact, name 12/20 #242424, vertical-align middle; "@" (at a word start) opens a 220-wide menu at the "@" (Add call transfer target / Share contact), then a 320-wide people search; the pick replaces the "@" with the pill and a space.
  - Custom hours: each day 15 below the last: name left, Available/Unavailable 16 before its switch (8 from the right); slots 8 under it and 8 apart, right-aligned: 120 x 32 filled-darker selects (#F5F5F5, no border), "to", 8 apart, then + (first slot, while under 5) or a trash button (24 x 23.3, 20 px icon, brand on hover); at five slots the first shows remove too.

- 2026-11-22 (agent setJ) built and verified:
  - AC1: MtmaHub.qml - the app-bar tile (at the bar's bottom, once another account is on the device) and Teams' flyout as measured: title, Unread/Channels/Chats pills, Filter by (Mentions, Tag mentions, Followed threads, Orgs submenu), per-account accordion with its count and Account settings (org row -> Switch), entries (unread activity with its kind disc, missed calls with Call/Chat, recent chats with previews), Scroll to see more. Data: each account's window publishes {missed, items, updated} to hub.json in its profile folder (Main.qml hubPublisher -> backend.publishHub -> config::write_hub_summary); others read them (backend.otherAccountsHubJson, every 5 s; an account with several profiles uses the running one, else the freshest). Picking an entry sends `open\t<thread>\t<name>` (or chatwith:/callback:<oid>) to that account's instance socket; its window comes forward and opens it (main.rs, backend.request_open_chat -> openChatRequested); not running: the account starts.
  - Verified on linuxlt: spatest (ost-test1, plain launch) published 31 entries, count 8; test2 with --setj-hub showed the tile (8), the flyout (380 x 562 at 70, bottom on the tile), Unread (18 of 31), Filter + Orgs, Account settings + Switch, and picking "OST Test 3" made spatest's window open it (its log: "another account's hub opened a chat here"); with spatest not running the pick started it (stopped by pid). Pictures matched Teams' layout.
  - AC2: the pills - Custom instructions keep each person as one object character in the plain-text box (richtext.cpp chips: a QTextObjectInterface registered by hand, its room = the pill + 2 px margins; QML draws the pill over it: border, #F5F5F5, Call brand / ContactCard #341A51 icon, name 12); "@" at a word start stays typed and opens the menu at it; the pick replaces it with the pill and a space; Save/length use the raw text with Teams' tags. Custom hours: 15/8 spacing, Available 16 before the switch 8 in, right-aligned 120 x 32 filled selects, 24 x 23.3 +/trash (brand on hover), the first slot's remove at five.
  - Verified on linuxlt (spatest, --setj-pa): ICD turned on, instructions with OST Test 2 (route) and OST Test 3 (contact) shown as pills (not saved), "@" typed -> menu at the "@" -> contact picked -> pill; raw text read back with Teams' tags; custom hours saved (Monday 9-5 and 6-7 PM, weekdays 9-5) and read back, pictured, then back to work hours (read back custom:false); ICD off again (read back).
  - Open: Pin this org (Teams pins an org's own tile to the app bar; not built - the pinned tile wasn't measured); OST's activity feed shows Graph-app activities with their raw template ids ("Q&A: teamsQnAEnabledForMeeting") where Teams words them ("Q&A is enabled for this event. Ask your questions!"), in the Activity view and so in the hub; an account's entries are as fresh as its own window (each account is its own OST profile). Test changes left: none on winpc (OST Test 2 signed out, ICD off, work hours); accounts.json on linuxlt was rewritten without "org" by another build meanwhile (OST falls back to the address).
<!-- SECTION:NOTES:END -->
