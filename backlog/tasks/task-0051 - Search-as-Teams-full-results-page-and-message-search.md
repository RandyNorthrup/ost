---
id: TASK-0051
title: 'Search as Teams: full results page and message search'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-11T03:01:00Z'
labels:
  - search
dependencies: []
references:
  - docs/parity/shell-settings.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Search P1 gaps (docs/parity/gaps-shell-calendar-files.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Enter opens Teams' full results page (Messages, People, Files, Teams and channels, Chats) with filters
- [x] #2 Message content search
- [x] #3 Find in chat (and Find in post in a thread window) opens Teams' find pane: keyword box, Messages / Date / From / Attachment / Mentions filters and results, as measured
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Find in chat / channel / post done (AC3): FindPane.qml (360 px pane in the main window; full-window in post and channel windows, with labelled pills), Substrate search (src/api/find.rs) with Teams' headers, query strings, filters (Messages/Files, Date, From, Attachment, Mentions, Type), results grouped by month, whole messages read for rows, terms marked in the opened message. Spec: docs/spec/find-in-chat.md.
- Not done: Teams' Send feedback footer (goes to Microsoft), Share on Loop files, and a "Notes" item Teams listed in a channel's Files from an uncaptured source.

- Search results page done (AC1, AC2): SearchView.qml (Teams' tabs All/Messages/Files/People/Channels/Group chats/+ Meetings, Images; per-tab filters Type, In (Substrate suggestions), Person (With/From), Date, More (@mentions me, Has attachment, Hide apps & bots), File Type; cards/rows as measured; Send feedback thumbs; "is:Tab" in the search box). src/api/search.rs sends Teams' own request bodies (src/api/search_requests/*.json) with the captured filter terms; message rows are read whole; Images pictures are cached as the chat caches them.
- Enter in the title bar search opens the page; results open where they were said with the terms marked.
- Follow-ups in TASK-105 (preview pane, Communities, Files grid view, uncaptured filter terms).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Search now works as Teams'.

- Find in chat / channel / post opens Teams' find pane, with the keyword box, filters and results (docs/spec/find-in-chat.md).
- Enter in the title bar's search opens Teams' full results page:
  - Tabs: All, Messages, Files, People, Channels, Group chats, Meetings and Images.
  - Filters: Type, In, Person (With / From), Date, More and File Type.
  - The Send feedback thumbs.
- Message content search sends Teams' own Substrate requests, with the filter terms captured from Teams.

Tests: api::find and api::search unit tests; --find-test and --search-page-test on linuxlt.
Follow-ups: TASK-0105 (preview pane, Communities, Files grid view, filter terms not yet captured).
<!-- SECTION:FINAL_SUMMARY:END -->
