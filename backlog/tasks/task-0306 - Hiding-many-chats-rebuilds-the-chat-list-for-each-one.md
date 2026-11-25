---
id: TASK-0306
title: Hiding many chats rebuilds the chat list for each one
status: To Do
assignee: []
created_date: '2026-11-25T18:10:00Z'
labels:
  - bug
  - chat
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while staging wiki demo data: hiding many chats in a row makes OST rebuild the whole chat list for every chat; its memory grew to about 13 GB before the instance was stopped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hiding or unhiding many chats (including a few hundred in a row, as when other clients hide them) updates the chat list without rebuilding it per chat, with no memory growth
- [ ] #2 OST's memory stays flat while chat-list updates arrive in bursts (live check on linuxlt)
<!-- AC:END -->
