---
id: TASK-0199
title: Meeting chat Q&A, Meeting Whiteboard and Breakout Rooms with rooms as Teams
status: To Do
assignee: []
created_date: '2026-11-16T09:43:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST lists a meeting chat's tabs as Teams (Attendance, Breakout Rooms, Q&A, Meeting Whiteboard) but Q&A and Meeting Whiteboard are Teams' embedded pages, which don't run without a TeamsJS host (TASK-0053): Whiteboard shows "Something went wrong" and Q&A's sign-in fails (AADSTS700054). Breakout Rooms' layout once rooms exist is unmeasured, and Assign participants, Room settings and Import from CSV only point to the meeting window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Q&A and Meeting Whiteboard tabs run in a meeting chat as in Teams
- [ ] #2 Breakout Rooms with rooms created matches Teams' layout, and its Assign participants, Room settings and Import from CSV work from the tab as in Teams
<!-- AC:END -->
