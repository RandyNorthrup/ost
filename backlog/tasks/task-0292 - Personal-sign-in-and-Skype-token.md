---
id: TASK-0292
title: Personal sign-in and Skype token
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0288
  - TASK-0290
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sign in with a personal Microsoft account the way Teams on the web for personal use does (its client, the consumers authority, teams.live.com redirect and origin), then get the Skype token and service map from teams.live.com's consumer authz. The leftover AuthConfig::personal() can't work (wrong redirect, refused scope) and is replaced.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A personal account signs in on Microsoft's own sign-in page in OST's window and stays signed in across restarts with silent token renewal
- [ ] #2 OST gets the consumer Skype token and the regional service URLs, and refreshes them before they expire
- [ ] #3 teams-cli can sign in with a personal account too
- [ ] #4 Tokens are stored in the keyring per account and never logged
<!-- AC:END -->
