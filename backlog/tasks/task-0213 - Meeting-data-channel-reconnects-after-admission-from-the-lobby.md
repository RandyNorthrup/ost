---
id: TASK-0213
title: Meeting data channel reconnects after admission from the lobby
status: To Do
assignee: []
created_date: '2026-11-17T02:43:00Z'
labels:
  - desktop
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0210: when OST is admitted from a meeting lobby, its meeting data channel doesn't come back after the media move. Give/take control now re-attaches on a new session, but anything else on the data channel (captions, reactions' channel messages, presenter layouts) may be lost after a lobby admission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After admission from the lobby, OST's meeting data channel reconnects and its features work as before, verified with Teams on winpc
<!-- AC:END -->
