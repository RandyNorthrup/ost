---
id: TASK-0111
title: 'Desktop: breakout rooms — organizer''s Join holds the main meeting'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T20:35:00Z'
updated_date: '2026-11-11T21:47:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop keeps an organizer's (or breakout rooms manager's) main meeting on hold when they join a room from its menu (breakoutRoomParticipantsService.leaveMainMeetingForParticipant skips organizers and managers), and goes back to it with Return. OST's Join leaves the main meeting as a participant's move does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An organizer who joins a room from its menu keeps the main meeting on hold and can go back to it
- [x] #2 The main meeting stays joined (on local hold, nothing sent or played) while the organizer is in the room, and its window shows Teams' On hold view with Resume
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams: organizer Join on a room menu (two windows, held main with Resume, Leave room / Leave meeting).
2. Backend: hold the main call locally, join the room, route the held call's events, resume or leave.
3. QML: held meeting window, Leave room button and menu, resume paths; live test as organizer.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop: Join opens the room in a second window; the main meeting window shows "Resume", greyed controls but Chat/Rooms/Leave, and "On hold mm:ss". Leave room (dropdown: Leave room, Leave meeting) closes the room and resumes the main meeting automatically.
- Teams' state is CallState.LocalHold; the cc hold link on a meeting leg answers resume with 430 "Unable to find a holdee", so OST holds locally (media held, leg kept).
- Resume: the join-time roster is stale; the live participants plus your saved roster entry (role) restore the view; the window's time carries on via nextConnectedAt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
An organizer's Join on a breakout room now holds the main meeting as Teams does.

- Main meeting on local hold (stays joined, media held); its own window: meeting time, Resume, greyed controls except Chat/Rooms/Leave, "On hold mm:ss".
- Room window: Teams' room bar (no Notes), "Leave room" with Leave room / Leave meeting.
- Leave room, Resume, a closed or ended room: back to the main meeting with its live people, your role and its time. Leave in the held window leaves the main meeting only.
- Held call's events are kept from the room's window except its rooms list; rooms stay managed from the room.
- Bar buttons widen for long labels.

Tested live (OST Test 2 organizing, Teams in the room): join, held window, Leave room, resume with organizer bar and time (harness --breakout-test --breakout-join). 447 unit tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
