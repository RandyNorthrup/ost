---
id: TASK-0218
title: Breakout room join details as Teams
status: To Do
assignee: []
created_date: '2026-11-17T06:54:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0216 left (docs/spec/call-and-meeting-window.md §1.8l): OST doesn't send meetingData {meetingCode, passcode} with a room's call (its source wasn't captured); while in a room Teams leaves the main conversation and at once rejoins it without a call (to keep the main meeting's updates), OST rejoins the main meeting in two steps instead; a failed room join shows an alert, not Teams' full retry screen in the room's window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Room calls carry meetingData and OST keeps the main conversation while in a room, as Teams
- [ ] #2 A failed room join shows Teams' retry screen in the room's window
<!-- AC:END -->
