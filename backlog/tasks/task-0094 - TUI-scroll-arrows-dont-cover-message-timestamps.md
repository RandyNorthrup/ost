---
id: TASK-0094
title: TUI scroll arrows don't cover message timestamps
status: To Do
assignee: []
created_date: '2026-11-10T15:58:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010). The messages pane draws its scroll indicators (^ at the top, v at the bottom) in the last column, over the last character of the first and last visible timestamps: "04:2^" for 04:24 (threads/00.txt) and "Mon 09:1v" for Mon 09:14 (general/06.txt).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Timestamps are never overwritten by the scroll indicators
- [ ] #2 The indicators still show when there is more to scroll
<!-- AC:END -->
