---
id: TASK-0268
title: In-room attendees as Teams (joined in a Teams Room)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-24T04:41:00Z'
updated_date: '2026-11-24T06:58:00Z'
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
- [x] #1 After adding a nearby Teams Room, OST shows Teams' Joined in room callout with Dismiss and Hide Attendees
- [x] #2 OST's People pane nests in-room participants under the room as Teams does
- [x] #3 Hide Attendees removes in-room attendees from the gallery as Teams does, verified live against Teams on winpc
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

- Built (4239a4b4): outgoing publish_meeting_room (PUT updateEndpointMetadata {holographicCapabilities 3, meetingRoom {email, mri}}) after add_room succeeds (Cast and Room audio; email from fetchShortProfile); roster Participant.meeting_room (kept across endpoint-less updates, as room now is); CallWindow myRoom / inSameRoom / hideSameRoom / shownOthers; "Joined in room" alert (Teams' calling alert card, once per call, not in room mode, ECS flags honoured when they say false); PeoplePane nested(): room row ringed, sub-items 36.3 in, brand line and end circle.
- Live (cast3/cast4, ost-test1 spatest casting to OST Test Room): the room's attach roster showed OST's endpoint meetingRoom {email ost-test-room@scnetsolutions.com, mri} exactly as Teams'; OST showed "Joined in room / You've joined OST Test Room. ..." with Dismiss / Hide Attendees like Teams'; People: OST Test Room with OST Test 1 (Organizer) nested under it with ring, line and circle as Teams'; Hide Attendees left only your own tile on the stage, as Teams (cast3 found the 2-person overlay still showing the room; fixed with shownOthers, cast4 verified).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now shows in-room attendees the way Teams does once you join in a nearby Teams Room (Cast or Room audio). Verified live with OST casting to OST Test Room, against Teams on winpc doing the same.

Changes (commit 4239a4b4):
- After the room is added, OST publishes its endpoint's meetingRoom {email, mri} (PUT updateEndpointMetadata). Teams' caster sends the same; the room's roster now shows OST's entry exactly like Teams'.
- The roster keeps each participant's meeting room (Participant.meeting_room) and no longer drops the room flag on updates without endpoints.
- Call window: "Joined in room" alert, once per call (not in room mode). Dismiss closes it; Hide Attendees takes the room and anyone in it with you off the stage for the rest of the call (Teams keeps this only in its client cache).
- People: in-room participants are nested under their room, with the brand ring, connector line and end circle measured from Teams.

Tests: new roster test the_room_a_laptop_joined_in_is_kept; lib 944 and desktop tests pass.

Open:
- Teams' way to show hidden attendees again was not found in the View menu, the room row menu or the Participants menu, so OST offers none either.
- New strings are not yet in untranslated.txt.
<!-- SECTION:FINAL_SUMMARY:END -->
