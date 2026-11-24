---
id: TASK-0268
title: In-room attendees as Teams (joined in a Teams Room)
status: To Do
assignee: []
created_date: '2026-11-24T04:41:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen on winpc 2026-11-23 while TASK-0228 cast to OST Test Room: once the laptop has added a nearby Teams Room (Cast, Room audio), Teams' meeting window shows a 'Joined in room' callout (You've joined <room>. To focus on remote participants, hide in-room attendees in the gallery; Dismiss / Hide Attendees) and its People pane lists the laptop's user nested under the room. OST shows neither. Research how Teams learns who is in the room (roster/participant mapping after the proximity invite) and the gallery's hide in-room attendees option.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After adding a nearby Teams Room, OST shows Teams' Joined in room callout with Dismiss and Hide Attendees
- [ ] #2 OST's People pane nests in-room participants under the room as Teams does
- [ ] #3 Hide Attendees removes in-room attendees from the gallery as Teams does, verified live against Teams on winpc
<!-- AC:END -->
