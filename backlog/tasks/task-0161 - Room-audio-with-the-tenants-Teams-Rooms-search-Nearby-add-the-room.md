---
id: TASK-0161
title: Room audio with the tenant's Teams Rooms (search, Nearby, add the room)
status: To Do
assignee: []
created_date: '2026-11-15T20:59:00Z'
labels:
  - calls
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' pre-join Room audio also finds the tenant's Teams Rooms: 'Search for a room' searches them, 'Other Suggestions' lists suggested rooms, 'Nearby' lists rooms found over Bluetooth/ultrasound (with Teams' Bluetooth and microphone hints), and joining adds the chosen room's audio system to the meeting. OST's picker (TASK-0159) has the connected room devices only; the test tenant has no Teams Room resource yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Typing in Room audio's picker finds the tenant's rooms as Teams does
- [ ] #2 Other Suggestions and Nearby list rooms as Teams does, with Teams' hints
- [ ] #3 Joining with a tenant room adds the room to the meeting as Teams does
<!-- AC:END -->
