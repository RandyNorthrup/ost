---
id: TASK-0080
title: Drag to reorder channel tabs as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T16:43:00Z'
updated_date: '2026-11-10T07:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lets you drag a channel's tabs into a new order (not the predefined ones), saved through the same pinned-tabs order as Move left/right. OST only has the menu moves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tabs that Teams lets you drag can be dragged, with Teams' drag feedback; predefined tabs can't
- [ ] #2 A drop saves the order with Teams' single-PATCH order algorithm, and Teams shows the new order
<!-- AC:END -->
