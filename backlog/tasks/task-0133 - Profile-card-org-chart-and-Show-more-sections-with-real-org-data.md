---
id: TASK-0133
title: Profile card org chart and Show more sections, with real org data
status: To Do
assignee: []
created_date: '2026-11-14T03:26:00Z'
labels:
  - desktop
  - people
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' profile card Organization tab draws an org chart (managers above, peers and reports) when the directory has managers; the test tenant has none, so Teams shows 'We don't have the necessary details…' (which OST now matches, with Home / Back / Next). The hover card's 'Show more' sections also failed to load in Teams on 2026-11-12. Needs managers set for test users (Entra) to measure Teams' chart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With managers set for test users, the Organization tab draws Teams' org chart and its navigation (Home, Back, Next) walks it as in Teams
- [ ] #2 The sections under Show more match Teams'
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->
