---
id: TASK-0022
title: Profile photos for people and teams
status: To Do
assignee: []
created_date: '2026-11-05T16:07:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop shows each person's profile photo (chat list, conversation, header) and each team's picture; OST draws initials everywhere. Reference: Windows Teams on winpc (ost-test1).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 People with a profile photo show it in the chat list, the conversation and the chat header, falling back to initials only when they have none
- [ ] #2 Teams and channels show the team's picture as Teams does
- [ ] #3 Photos are cached on disk owner-only and refreshed, not refetched on every view
<!-- AC:END -->
