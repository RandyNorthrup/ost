---
id: TASK-0186
title: Call park, transfer-consult and merge as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-17T15:02:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's toolbar knows Teams' merge and park buttons but never enables them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Park, retrieve and merge calls work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-17 (16255e9): the engine holds one call while placing a second. Consult starts a call ("Open chat" keeps the chat consult); the banner offers Transfer (Teams' transfer request naming the replaced call), Merge Calls (three-person group chat, invite, leave the held call) and End consult. Unit-tested against Teams' calling code. Harness: --consult-call, --consult-transfer, --consult-merge.
- Not yet live: needs a third user. ost-test3 was created; the user approved a Business Basic licence for it and the Teams Phone Standard trial for Park (2026-11-17).
- Not built: the receiving side of a consult transfer.
<!-- SECTION:NOTES:END -->
