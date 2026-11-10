---
id: TASK-0096
title: TUI keeps every @mention's name in the message text
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
Found on the TUI UX tour (TASK-0010). In OST group test, "OST test 54: mention for check" shows with the mentioned person missing (group/12.txt), while the next message shows "OST test 54: mention for Randy Northrup check". Other mentions in General (channel, team and tag mentions, OST TEST 60–70) keep their names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every mention in the tour's chats shows the mentioned name
- [ ] #2 The cause is covered by a unit test with the message's real content
<!-- AC:END -->
