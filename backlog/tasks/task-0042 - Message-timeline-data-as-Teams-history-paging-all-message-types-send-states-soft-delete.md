---
id: TASK-0042
title: >-
  Message timeline data as Teams: history paging, all message types, send
  states, soft delete
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
labels:
  - desktop
  - messages
dependencies: []
references:
  - docs/spec/messages-and-composer.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Timeline data gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/messages-and-composer.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Older messages load on scroll-up (Teams' paging)
- [ ] #2 Every message type Teams shows per chat kind renders (system/control events incl. member added and rename, call rows with bold duration, cards, files, media)
- [ ] #3 Optimistic send with Sending/Retrying/failed states and Retry/Edit/Delete
- [ ] #4 Delete is Teams' soft delete with the tombstone and Undo
- [ ] #5 Read receipts: Teams' Seen rule (at most two icons, 2-20 members); typing indicator with Teams' timeouts and multiple typers
<!-- AC:END -->
