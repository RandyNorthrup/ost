---
id: TASK-0229
title: 'TUI: live messages and unread counts'
status: To Do
assignee: []
created_date: '2026-11-20T01:21:00Z'
labels:
  - tui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from TASK-0002, which was marked Done with these two criteria never met: the terminal client has no live push (no trouter connection) and its sidebar unread counts are always 0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Incoming messages appear in the TUI in real time via Teams' push (trouter), as in the desktop app
- [ ] #2 Unread counts on channels and chats in the TUI sidebar reflect the real unread state
<!-- AC:END -->
