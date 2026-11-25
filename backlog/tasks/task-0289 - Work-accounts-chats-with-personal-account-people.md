---
id: TASK-0289
title: 'Work accounts: chats with personal-account people'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0288
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal-account users can already chat with work users when the tenant allows it. OST shows those 8:live: members without proper names, pictures or the External label Teams shows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In a work account, a chat with a personal-account user shows their name, picture and Teams' External label, as Teams desktop does
- [ ] #2 A work user in OST can start a chat with a personal account by email, as in Teams, and messages flow both ways (ost-test1 with a personal test account)
- [ ] #3 Buttons Teams disables for personal-account chats (calls, screen sharing, file limits) are disabled the same way in OST
<!-- AC:END -->
