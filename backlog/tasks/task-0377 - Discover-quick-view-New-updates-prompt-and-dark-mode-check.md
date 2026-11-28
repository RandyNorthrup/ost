---
id: TASK-0377
title: 'Discover quick view: New updates prompt and dark mode check'
status: In Progress
assignee:
  - '@t377'
created_date: '2026-11-28T00:08:00Z'
updated_date: '2026-11-28T01:42:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 discover-surface bundles and worker for the New updates rule; capture Teams web (OST Test 2) worker requests with Discover open to time the polls.
2. Build the poll (ECS discoverPollingInterval, 5 min), first-post comparison and Teams' New updates button in DiscoverView.
3. Measure Teams web Discover in light, dark and High contrast (computed styles, Fluent tokens) and fix OST's colours.
4. Reply from a Discover card live: Teams web (OST Test 2) and OST (test account) in OST Test Team, deleting each reply.
5. Harness --discover-poll-test / --discover-reply=, spec section, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: replying from a Discover card (DiscoverView.qml replyInput/sendReply, TASK-0365 PR #56) and theme-token colours are built but not checked live; the New updates prompt is left.
<!-- SECTION:NOTES:END -->
