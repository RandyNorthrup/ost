---
id: TASK-0071
title: People pane binding loop on itemWidth
status: To Do
assignee: []
created_date: '2026-11-09T07:21:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PeoplePane.qml line 508 logs 'Binding loop detected for property itemWidth' while a meeting's People pane is open; the layout should settle without a loop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Opening and resizing the People pane in a meeting logs no binding loop
- [ ] #2 Rows keep Teams' measured widths
<!-- AC:END -->
