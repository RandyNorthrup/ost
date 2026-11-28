---
id: TASK-0378
title: Ended channel meeting cards show No title and year -0001
status: To Do
assignee: []
created_date: '2026-11-28T00:50:00Z'
labels:
  - desktop
  - channels
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen during TASK-0369 live checks: in OST test channel, ended channel-meeting cards show 'No title, Sunday, December 31, -0001' instead of the meeting's title and date, which looks like a zero/unset date and missing subject being formatted. Find the source message shape and match what Teams shows for the same cards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ended channel-meeting cards in OST test channel show the same title and date as Teams desktop for the same posts
- [ ] #2 A unit test covers the message shape that produced the zero date
<!-- AC:END -->
