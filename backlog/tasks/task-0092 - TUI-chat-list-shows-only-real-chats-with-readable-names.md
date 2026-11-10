---
id: TASK-0092
title: TUI chat list shows only real chats, with readable names
status: To Do
assignee: []
created_date: '2026-11-10T15:39:00Z'
labels:
  - tui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The TUI's chat list includes the account's system streams (48:drafts, 48:threads, 48:notifications, 48:calllogs, 48:saved, 48:mentions) as chats, some named only by their id; opening 48:drafts fails with HTTP 400. Several real chats also show as raw thread ids (19:Ikvn…, 19:ldSo…, 19:4287e791…) instead of their names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 System streams (48:*) are not listed as chats, except the notes-to-self chat, which shows as '<name> (You)'
- [ ] #2 Every listed chat shows a readable name (topic, or the other members' names) instead of a raw id
- [ ] #3 Opening any listed chat loads its messages without an error
<!-- AC:END -->
