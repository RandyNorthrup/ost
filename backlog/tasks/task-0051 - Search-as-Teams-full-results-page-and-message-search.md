---
id: TASK-0051
title: 'Search as Teams: full results page and message search'
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-11T01:40:00Z'
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
- [ ] #1 Enter opens Teams' full results page (Messages, People, Files, Teams and channels, Chats) with filters
- [ ] #2 Message content search
- [x] #3 Find in chat (and Find in post in a thread window) opens Teams' find pane: keyword box, Messages / Date / From / Attachment / Mentions filters and results, as measured
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Find in chat / channel / post done (AC3): FindPane.qml (360 px pane in the main window; full-window in post and channel windows, with labelled pills), Substrate search (src/api/find.rs) with Teams' headers, query strings, filters (Messages/Files, Date, From, Attachment, Mentions, Type), results grouped by month, whole messages read for rows, terms marked in the opened message. Spec: docs/spec/find-in-chat.md.
- Not done: Teams' Send feedback footer (goes to Microsoft), Share on Loop files, and a "Notes" item Teams listed in a channel's Files from an uncaptured source.
<!-- SECTION:NOTES:END -->
