---
id: TASK-0293
title: 'Personal accounts: chat list, messages and chat requests'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0292
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal accounts use the consumer chat service (msgapi.teams.live.com) with consumer headers. Teams for personal use also has chat requests: people who aren't your contacts send a request you can preview, accept or block.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The chat list, reading, sending, editing, deleting, reactions and attachments work for 1:1 and group chats with a personal account, with Teams' layout
- [ ] #2 New 1:1 and group chats can be started by name, email or phone, as Teams for personal use does
- [ ] #3 Chat requests show with Preview, Accept and Block as on Teams desktop, and the sender sees the pending state
- [ ] #4 Features Microsoft retired for personal accounts (polls, tasks, location sharing, SMS) are not shown
<!-- AC:END -->
