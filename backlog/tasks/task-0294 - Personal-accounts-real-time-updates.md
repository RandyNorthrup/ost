---
id: TASK-0294
title: 'Personal accounts: real-time updates'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0293
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Messages, typing, read receipts and calls arrive for work accounts over Trouter. Personal accounts use the consumer Trouter and registrar (TFL registration); one source says chat messages don't arrive by push there and polls instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New messages, typing and read receipts appear within seconds for a personal account
- [ ] #2 If push doesn't deliver chat messages, OST polls like Teams' web client does, without extra load when idle
- [ ] #3 Incoming calls and notification banners work for a personal account
<!-- AC:END -->
