---
id: TASK-0228
title: Cast to a Teams Room as Teams
status: To Do
assignee: []
created_date: '2026-11-20T01:10:00Z'
updated_date: '2026-11-20T04:40:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's Cast window searches and reports no rooms (TASK-0166). Since TASK-0161 OST can run as a Teams Rooms device (OST Test Room, room mode, Bluetooth beacon), so Cast can now be built and checked end to end: finding the room nearby and casting content to it as Teams does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cast finds the nearby Teams Room as Teams does
- [ ] #2 Casting to the room shows the content on the room as Teams does, verified live with OST in room mode and against Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 (agent c3) research (cast-app 651787, 527114 joinCallFromIntent, 81744 AddRoomScreen, Rooms 26198 byomAutoAccept): Cast has no protocol of its own. Wizard steps Rooms ("Select a nearby Teams Room", BLE nearbyRooms only, presence label by activity, nearby icon when it has a code, single room auto-picked, 20 s search, Bluetooth-off hint) / Meetings (calendar now±60 min with a Teams link; "Just cast" default; skipped when none) / Content (share tray in Cast mode 448x480: screens, windows, PowerPoint Live, system audio). Cast = fireCallingIntent Meeting {outgoingAudio/incomingAudio/outgoingVideo false, context cast, meeting {isCast, showPrejoin false, title room name, roomParticipantToAdd, sharing source | pptSharingSource, shareSystemAudioCasting}}; Just cast = instant meeting (MeetNow). On Connected: startScreenSharingOnCall / startPptSharingForCall, then addRoomParticipant(..., proximityValidationCode re-read from the live BLE scan, source Bluetooth, isProximityJoin false) = the same addParticipantAndModality proximity invite as Room audio. Room side: ordinary BYOM auto-accept (token, salt valid); home tooltip "Cast to this room with:" / "Teams Cast"; no cast-specific screen. Theme sizes from 103464 (isCastHeader 60, isCastFooter 90, Next/Back 52 in, summary max 300, list items 536x80 radius 2 gap 8, body paddingTop 12, tray 448x480).
- Built: CastWindow wizard (rooms/meetings/content, footer Back/summary/Next|Cast), Main startCast (castMeetNow or the picked meeting, muted/no audio/no camera, share once connected, addRoomToMeeting with the live code), backend castMeetings / castMeetNow ops, nearby rooms with presence activity (refreshed every 30 s), RoomHome cast tooltip, harness --cast-test.
<!-- SECTION:NOTES:END -->
