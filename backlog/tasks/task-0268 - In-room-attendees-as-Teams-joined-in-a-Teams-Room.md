---
id: TASK-0268
title: In-room attendees as Teams (joined in a Teams Room)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-24T04:41:00Z'
updated_date: '2026-11-24T05:34:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find what Teams keys in-room on: room's attach roster during Teams' cast (OST_TROUTER_DUMP_DIR attach-reply dump).
2. Caster: after adding the room, PUT updateEndpointMetadata with meetingRoom {email, mri}.
3. Roster: Participant.meeting_room; QML: isInSameRoom, Joined in room alert (once a call), Hide Attendees (gallery, call only), People nesting.
4. Verify live: OST cast to OST room, compare with Teams screenshots from winpc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 research (castT): Teams' caster endpoint carries endpointMetadata.meetingRoom {email: ost-test-room@scnetsolutions.com, mri: 8:orgid:<room>} (room's attach roster, additionalActionResponses[0].output.roster). Teams derives mappedToMeetingRoom from it (Mv), isInSameRoom (lw: the room itself or anyone whose endpoint names the same room), the UnhideRoomParticipantsUfd "Joined in room" (once, when mapped; ECS Host enableHideSameRoomParticipants + Calling enableHybridCompanionJoinUfd), Hide Attendees = client-cache shouldHideSameRoomParticipants (not persisted), and People sub-items (room ring, line, end circle).
- Seen on winpc: after Hide Attendees the gallery dropped the room tile, leaving only your own; People: OST Test Room with OST Test 1 (Organizer) nested under it.
<!-- SECTION:NOTES:END -->
