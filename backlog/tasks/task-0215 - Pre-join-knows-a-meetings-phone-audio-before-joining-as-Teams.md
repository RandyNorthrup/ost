---
id: TASK-0215
title: Pre-join knows a meeting's phone audio before joining, as Teams
status: To Do
assignee: []
created_date: '2026-11-17T04:07:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams knows before you join whether Phone audio is available because it quietly joins the call while the pre-join window is open (TASK-0187, docs/spec/call-and-meeting-window.md §1.8k). OST reads the calendar invite's dial-in block instead, so for meetings OST creates (no dial-in block in their invite) Phone audio is greyed out before joining, although dial-in works once in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pre-join offers Phone audio exactly when Teams does, for meetings created by Teams and by OST
<!-- AC:END -->
