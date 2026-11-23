---
id: TASK-0258
title: 'Calendar dark theme: event fills, mini-month week and header lines as Teams'
status: To Do
assignee: []
created_date: '2026-11-23T17:39:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0255 gave the work week grid Teams' dark palette (days, hours outside the working day, grid lines). In dark theme OST still draws other calendar parts with light colours: event fills (#C7C9EE/#E1E1F6), the mini month's selected week strip, the #E0E0E0 header and month lines and the dashed slot lines. Teams' hosted calendar takes them from its dark palette (measured 2026-11-23: themeLighter #2F2F4A, themeLighterAlt #2B2B40, neutralQuaternary #3D3D3D, neutralLight #141414, ...).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every calendar view (day, work week, week, month, mini month, event cards) draws Teams' dark colours in dark theme, measured on winpc
<!-- AC:END -->
