---
id: TASK-0111
title: 'Desktop: breakout rooms — organizer''s Join holds the main meeting'
status: To Do
assignee: []
created_date: '2026-11-11T20:35:00Z'
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
- [ ] #1 An organizer who joins a room from its menu keeps the main meeting on hold and can go back to it
- [ ] #2 Teams shows the organizer still in the main meeting (on hold) while they are in the room
<!-- AC:END -->
