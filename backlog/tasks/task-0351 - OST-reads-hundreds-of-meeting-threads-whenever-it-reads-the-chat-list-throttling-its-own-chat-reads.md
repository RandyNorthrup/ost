---
id: TASK-0351
title: >-
  OST reads hundreds of meeting threads whenever it reads the chat list,
  throttling its own chat reads
status: To Do
assignee: []
created_date: '2026-11-27T14:32:00Z'
labels:
  - chat
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0350's live checks (2026-11-27): each chat-list read makes OST (api::chat::meeting_backroom) GET /v1/threads/{id}?view=msnp24Equivalent for every titled meeting chat it hasn't classified (~220 for OST Test 1, up to 180 per second). The chat service's per-user quota (429 'API calls quota exceeded! 20Per10SecswithDepth6', Retry-After 0) then refuses most of them, and since a refused read isn't remembered the next chat-list read (start-up, a new chat appearing) asks for all of them again. Every other thread read in that window fails too: opening a chat, a call's members, the activity feed. Teams doesn't read meeting threads in bulk.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reading the chat list doesn't cause the chat service to throttle OST's thread reads (no burst of meeting-thread reads), while backroom/event chats are still named as Teams names them, verified live as OST Test 1
<!-- AC:END -->
