---
id: TASK-0037
title: 'Desktop: breakout rooms (Rooms) for organizers'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-11T20:35:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rooms is shown to organizers and greyed. Teams manages breakout rooms through the conversation's meeting-group links (updateMeetingGroups, joinMeetingGroup).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An organizer can create rooms, assign people and open or close them
- [x] #2 Participants are moved into their room and back
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Participant side: follow assignedBreakoutRooms updates (localParticipantUpdate), move to the room as Teams does (join room, then leave main), return when the closed room ends; fix leg retarget after lobby admission and end-event attribution.
2. Capture the organizer API responses (create, open, close, settings, bulk/details, assign) from Teams desktop on winpc.
3. api::breakout_rooms module + backend invokables.
4. Native Rooms panes as Teams: Create breakout rooms, Breakout rooms (manage), Assign participants, room menu, settings.
5. Measure Teams participant UI (OST Test 2 organizes, Teams joins) and match it.
6. Unit tests, live test both directions, commit, backlog, remaining-work page.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Protocol: rooms are managed through the mt middle tier (beta/breakoutRoom/...), not the conversation's meeting-group links.
- Participant: conversation/localParticipantUpdate body.breakoutDetails.mainMeetingProperties.assignedBreakoutRooms [{name,isOpen,meetingJoinUrl,allowMoveParticipantsAutomatically,moveJitter}].
- Teams (breakoutRoomParticipantsService) joins the room first, then leaves the main call once the room is connected; when the server ends a closed room (~30-40 s after close) it goes back after the move jitter.
- Bug found: after lobby admission the leg is retargeted (call/mediaAcknowledgement "Participant retarget was successful." with new callLeg/hold/transfer links); OST kept the lobby leg, so Leave did not end the meeting leg. Fixed (OutgoingCall::retarget).
- Bug found: a stale leg's call/end was taken as the end of the current call; ends naming a call we moved out of are now ignored.

- Organizer UI measured on winpc (Create, Breakout rooms, Settings, Assign, Rename, Delete, Remove, Announcement, Import CSV) and built natively; live organizer state from allBreakoutRooms on the organizer's call.
- Teams' own participants are moved by a server invite (10 s countdown alert); OST acts on assignedBreakoutRooms and shows the same alerts. Closing is seen in the room as breakoutRoomProperties.restrictChatAccess=true.
- Announcements go through the middle tier (beta/breakoutRoom/announce); Teams in the room got them as a Room 1 chat notification. Teams desktop's own announcement goes through its native stack.
- Each placed call's callbacks carry a tag (…/x<tag>/callAgent/…) so events of a meeting we moved out of are ignored.
- Organizer Join from a room menu leaves the main meeting (Teams holds it): TASK-0111.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Breakout rooms work in OST as in Teams desktop, for organizers and participants.

Organizers:
- Rooms pane: Create breakout rooms (count; automatic, manual or self-chosen assignment), Breakout rooms (assignment card, Open/Close rooms, Add room, Import from CSV, Make an announcement, Remove rooms, Rooms settings; room menu Join/Open/Rename/Close/Delete; people and "In room"), Settings (presenters as managers, time limit "HH:MM:00", auto-move, self-select, return).
- Dialogs: Assign participants (search, Select a room, Shuffle: Everyone / Only unassigned people), Rename, Announcement, Delete room, Remove rooms, Import CSV (template download, Teams' limits and warnings, overwrite confirmation).
- api::breakout_rooms: create, bulk list, bulk/v2 assign, open, close, settings, add, rename, delete, delete all, announce; newVersion = participantId_uuid. Live state from allBreakoutRooms on the organizer's call.

Participants:
- "Join room" leads the bar while the assigned room is open; the 10 s alerts before moving in and back; rooms hide Notes; "Return" when allowed. The room is joined first and the main meeting left once it answers.

Fixes:
- Lobby-admitted meetings: the call leg is retargeted on admission (call/mediaAcknowledgement); OST now hangs up the right leg (Leave used to leave the meeting's leg alive).
- Call events are tagged per call, so a meeting we moved out of can't end the current one.

Tests: 447 unit tests (new: breakout parsing, API shapes, CSV import, leg retarget, callback tags, ubar Join room/Notes). Live on winpc + linuxlt: Teams organizer with OST participant (move in, alerts, back, Leave) and OST organizer with Teams participant (create, assign, open, announce, close, remove).

Follow-up: TASK-0111 (organizer's Join holds the main meeting).
<!-- SECTION:FINAL_SUMMARY:END -->
