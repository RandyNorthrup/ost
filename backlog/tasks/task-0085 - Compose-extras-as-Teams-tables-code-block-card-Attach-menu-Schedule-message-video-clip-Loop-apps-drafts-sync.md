---
id: TASK-0085
title: >-
  Compose extras as Teams: tables, code block card, Attach menu, Schedule
  message, video clip, Loop, apps, drafts sync
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T23:01:00Z'
updated_date: '2026-11-10T15:31:00Z'
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
- [ ] #1 Tables can be inserted and edited from the formatting bar and are sent and shown as Teams does
- [x] #2 Code blocks show Teams' card menu and syntax colours
- [ ] #3 Attach offers Teams' menu (OneDrive / cloud files, browse channels, upload) and sends what it picks as Teams does
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
<!-- SECTION:NOTES:END -->
