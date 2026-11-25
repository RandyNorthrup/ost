---
id: TASK-0299
title: 'Personal accounts: calls and meetings'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0294
  - TASK-0298
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal-account calls go through the consumer conversation service with the Skype token and may need browser-style media (DTLS-SRTP, BUNDLE) instead of the format OST uses for work calls. Free meetings are limited to 60 minutes and 100 people (Microsoft 365 Personal or Family raise this); recording needs a subscription and is kept 30 days in the meeting chat.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 1:1 audio and video calls and group calls from a chat work between personal test accounts and with Teams on winpc
- [ ] #2 Meet now and scheduled personal meetings work, including joining as a guest, with Teams' meeting roles and options
- [ ] #3 The meeting limits, warnings and upgrade prompts match Teams for a free account
- [ ] #4 Features Teams doesn't offer personal accounts (breakout rooms, Whiteboard, avatars) are not shown
<!-- AC:END -->
