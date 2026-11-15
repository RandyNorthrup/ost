---
id: TASK-0163
title: 'Chat list: chats with no messages as Teams'
status: To Do
assignee: []
created_date: '2026-11-15T23:27:00Z'
labels:
  - desktop
  - chat-list
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A group chat created with members but no messages (OST large chat test, made through the chat service on 2026-11-15) was not in Teams' chat list on winpc even after a restart; it appeared once OST TEST 160 was sent. OST listed it straight away. Find Teams' rule for listing chats that have no messages yet and match it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Teams' rule for when a chat with no messages is listed is found in its code and checked on winpc
- [ ] #2 OST's chat list follows the same rule
<!-- AC:END -->
