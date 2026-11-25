---
id: TASK-0290
title: 'Several accounts: add a personal account, switch, sign out one'
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
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop runs one personal account next to work accounts: the profile menu has Add another account, lists the accounts to switch between, and signs out of one account without the others. OST signs in to one account per profile today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The profile menu lists the signed-in accounts with Add another account and Sign out, matching Teams desktop (verified side by side on winpc)
- [ ] #2 Each account keeps its own tokens, settings and caches; switching shows the other account without signing in again
- [ ] #3 Only one personal account can be added, with Teams' message when a second is tried
- [ ] #4 Signing out of one account leaves the others signed in
<!-- AC:END -->
