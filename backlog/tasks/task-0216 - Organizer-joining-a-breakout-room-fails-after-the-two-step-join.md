---
id: TASK-0216
title: Organizer joining a breakout room fails after the two-step join
status: To Do
assignee: []
created_date: '2026-11-17T04:26:00Z'
labels:
  - desktop
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression from TASK-0187's two-step meeting join (conversation, then call), found during TASK-0213: in --breakout-test --breakout-join (OST Test 2's own meeting), the conversation join and call request succeed, then the server ends it with "Conversation ending after breakout room is not open. (403)". OST shows "Couldn't join the meeting" and closes the call window although it had just returned to the main meeting; the room's call acceptance arrives after OST gave up, so that leg may dangle. The same flow worked before (TASK-0111, 2026-11-11).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An organizer and a participant join and leave breakout rooms as in Teams, with the two-step join, verified with Teams on winpc
- [ ] #2 A failed room join never closes the main meeting's window or leaves a call leg behind
<!-- AC:END -->
