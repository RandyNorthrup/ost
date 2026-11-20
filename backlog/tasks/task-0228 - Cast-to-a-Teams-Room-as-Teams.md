---
id: TASK-0228
title: Cast to a Teams Room as Teams
status: To Do
assignee: []
created_date: '2026-11-20T01:10:00Z'
updated_date: '2026-11-20T06:42:00Z'
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

- Room side fix: a room invited into a meeting answers it as an incoming call, which had neither the meeting's roster at the attach nor content-sharing joins, so a cast PowerPoint only reached it when the caster left. Now the attach's join answer (roster.participants) goes through the roster pipeline, and ActiveCall joins content sessions (POST sessionInformation.contentSharingController with its own callbacks) and takes their updates/ends, as a meeting join does. Also PptLiveStage's late-XHR start race guarded.
- Verified live (linuxlt, emulated btvirt pair: room OST_PROFILE=room advertising on hci1, ost-test1 scanning on hci2): Cast listed "OST Test Room" (Available, nearby glyph, picked by itself), no meetings step (none within the hour), content = PowerPoint Live "OST TEST 228 cast.pptx" (a test deck in ost-test1's OneDrive; the Office recent list was empty, harness --cast-ppt-file); Cast: Meet now titled "OST Test Room", joined without audio/camera, PPT Live presented (content sharing 202), room added with the live beacon code; the room auto-accepted (Bluetooth, valid salt, in tenant), got the roster at the attach, joined the PPT session (200) and showed the deck ("OST TEST 228 cast", 1 of 2) in its call window titled "OST Test Room | OST". --cast-end ended the meeting; the room's call ended (logs). Earlier run without --cast-end: the room stays in an empty Meet now (its auto exit only leaves ad hoc meetings / after a valid end time), ended by the organizer.

- 2026-11-19 "Cast and join" (scheduled "OST TEST 228 cast and join" in ost-test1's calendar, listed in the meetings step and picked): the laptop joined it, presented the deck, the room auto-accepted with the meeting's title "OST TEST 228 cast and join"; ended with --cast-end, room's call ended. Found: the room's roster updates can arrive before its answer (and the attach roster is older), so the presented session was known before there was a call to join it with; now the attach roster only adds people not heard of yet and, once answered, what is presented is joined afresh.

- Final run (cast10, after the roster fix): "Cast and join" OST TEST 228 cast and join -> the room auto-accepted, learned the deck from its roster, joined the PowerPoint Live session (content sharing: joined) and showed it; ended with --cast-end, the room's call ended. Cleanup: the meeting deleted, the test deck removed from ost-test1's OneDrive, rooms stopped, btvirt pair taken down.
- Open: (1) Teams side-by-side on winpc not done (winpc was in use); wizard card/check colours follow Teams' v0 dark theme structure, not measured; (2) screen/window content on Linux goes through the desktop's portal picker after Cast (KDE's can't be driven here, so live runs used PowerPoint Live); (3) the room stays in an emptied Meet now (its auto exit leaves only ad hoc meetings or after a valid end), as the Teams Rooms rule OST copies.
<!-- SECTION:NOTES:END -->
