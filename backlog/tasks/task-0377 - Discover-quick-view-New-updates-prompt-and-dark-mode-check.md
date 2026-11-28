---
id: TASK-0377
title: 'Discover quick view: New updates prompt and dark mode check'
status: To Do
assignee: []
created_date: '2026-11-28T00:08:00Z'
updated_date: '2026-11-28T01:04:00Z'
labels:
  - desktop
  - chat
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0365 (PR #56): Teams' Discover feed shows a New updates prompt when new posts arrive; OST doesn't (how often Teams checks wasn't measured). Discover was also not checked in dark or high-contrast themes, and sending a reply from a Discover card wasn't tried live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Discover shows Teams' New updates prompt at Teams' refresh rule (measured and documented)
- [ ] #2 Discover matches Teams in dark and high-contrast themes
- [ ] #3 Replying from a Discover card works as in Teams (checked live with test accounts)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: replying from a Discover card (DiscoverView.qml replyInput/sendReply, TASK-0365 PR #56) and theme-token colours are built but not checked live; the New updates prompt is left.
<!-- SECTION:NOTES:END -->
