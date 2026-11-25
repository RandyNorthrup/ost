---
id: TASK-0297
title: 'Personal accounts: app shell, settings and plans'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0292
  - TASK-0290
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For a personal account Teams' left rail is Chat, Meet, People, Calendar and Activity (no Teams and channels, Files, Calls or Apps store), and Settings has its own set of pages, including Privacy options (who can find, call or add you to groups), People, Files and links, and Plans and upgrades.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A personal account shows Teams' left rail and hides every work-only feature (teams and channels, Files, Calls app, Apps store, Copilot where unavailable, Premium)
- [ ] #2 Settings shows the pages and options Teams shows for a personal account, synced with the account, with the personal-account Privacy options
- [ ] #3 Plans and upgrades shows what Teams shows; buying opens Microsoft's page in the browser
- [ ] #4 Feature flags come from ECS with the personal-account (TflNorthstar) configuration
<!-- AC:END -->
