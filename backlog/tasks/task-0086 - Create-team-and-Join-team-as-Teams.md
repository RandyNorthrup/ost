---
id: TASK-0086
title: Create team and Join team as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-10T04:20:00Z'
updated_date: '2026-11-10T04:20:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Your teams and channels has Teams' Create team split button (Create team, Join Team). Teams opens its Create a team flow (team name, description, privacy, first channel, sensitivity; templates) and the Join team gallery (search public teams, Join with a code). OST has neither, so the button does nothing. The tenant rule allows no new teams and no joining real teams, so creating/joining can only be verified up to the request Teams would send.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Create team opens Teams' Create a team flow, measured against Teams, and creating a team sends Teams' request
- [ ] #2 Join Team opens Teams' join gallery (search, public team cards, Join a team with a code), measured against Teams
- [ ] #3 Verified side by side with Teams on winpc without creating or joining a team
<!-- AC:END -->
