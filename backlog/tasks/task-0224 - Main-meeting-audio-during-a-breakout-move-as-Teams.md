---
id: TASK-0224
title: Main meeting audio during a breakout move as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-18T08:38:00Z'
updated_date: '2026-11-18T09:22:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0222: while a participant is being moved into a breakout room, Teams keeps the main meeting's audio playing until the room's call connects; OST silences it at once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 During a move into a breakout room, OST keeps the main meeting audio until the room connects, as Teams does, verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- edcd913: before a participant's move, OST only turns the camera off; audio keeps flowing both ways until the new meeting answers, then OST leaves the old one (as in Teams' move code). An organizer's Join from a room's menu still holds the main meeting.
- Live (linuxlt, meeting3, test2 organizer, ost-test1 participant): main → Room 1 kept playing and sending (about 50 packets a second) and wasn't held; Room 1 → main likewise.
- Merged 2026-11-18: build OK, 724 lib tests passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Keeps the main meeting's audio during a breakout move until the room connects, as Teams does.

- src/calling: a participant's move turns the camera off instead of holding the old meeting, and leaves it once the new one answers; each move logs the old meeting's audio counters.
- Verified live with the breakout harness; 724 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
