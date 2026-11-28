---
id: TASK-0300
title: 'Personal accounts: files in chats and personal OneDrive'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T03:34:00Z'
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
Files sent in personal-account chats go to the Microsoft Teams Chat Files folder of the sender's personal OneDrive (5 GB free; photos and videos don't count). There is no Files app for personal accounts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sending and opening files and photos in chats works as in Teams for personal use, stored where Teams stores them
- [ ] #2 The chat's Files tab and the storage-full message match Teams
- [ ] #3 A personal account's chats have Teams' Photos tab (the gallery of the chat's pictures), next to Chat and Files (TASK-0293 shows Chat and Files only)
<!-- AC:END -->
