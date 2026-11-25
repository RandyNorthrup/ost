---
id: TASK-0301
title: OneDrive Recent after Graph drive/recent is retired
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies: []
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Microsoft stops returning data from Graph /me/drive/recent after November 2026. OST's OneDrive and file picker use it for work accounts today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST's Recent files lists (OneDrive, file pickers, Files) keep working without /me/drive/recent, with the same items Teams shows
<!-- AC:END -->
