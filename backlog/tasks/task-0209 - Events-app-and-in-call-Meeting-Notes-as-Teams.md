---
id: TASK-0209
title: Events app and in-call Meeting Notes as Teams
status: To Do
assignee: []
created_date: '2026-11-16T22:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0038 (docs/spec/app-host.md):
- Events is not a web page in Teams: Teams draws it itself (Discover and Manage tabs, Create event) from the virtual-events API. OST's app bar still opens Teams on the web for it.
- The call window's Notes button gets or makes the meeting's notes through Teams' meeting-notes service and shows them as a Loop page (read from Teams' code, not captured live). OST's Loop host (TASK-0205) can show the page.
Immersive Reader on messages with cards also needs the card text added, as Teams does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Events opens natively in OST with Teams' Discover and Manage tabs and Create event, as in Teams
- [ ] #2 The call window's Notes opens the meeting's notes as Teams does
- [ ] #3 Immersive Reader includes a card's text as Teams does
<!-- AC:END -->
