---
id: TASK-0226
title: Teams Rooms mode leftovers
status: To Do
assignee: []
created_date: '2026-11-19T07:00:00Z'
updated_date: '2026-11-19T10:47:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0161: the room's call window shows the caller's name instead of the meeting title after an invite; the end-of-meeting dialog wording comes from a forum quote because Teams' own string isn't in this install.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The room's call window shows what a Teams Rooms device shows after accepting an invite, verified live
- [ ] #2 The end-of-meeting dialog's text and timing come from Teams Rooms' own strings and match it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research: Teams Rooms' own strings come from the Teams Rooms build of Teams (MSTeams-Rooms-x64.msix 26198.304 inside the Teams Rooms on Windows 5.7.112 package, CreateSrsMedia go.microsoft.com/fwlink/?linkid=2151817; unpacked on linuxlt ~/teams-rooms, keys unhashed). meetingRoomConsole: meeting_room_auto_exit_dialog_title "About to leave meeting ...", Snooze, Leave now; meeting_room_default_meeting_title "Microsoft Teams Meeting".
- Auto exit (RigelAutoExitMeetingManager, same in desktop 26304): 300 s scheduled / 60 s ad hoc after the end with nobody else in, snooze 900 s, bar 15 s (25 ms steps); ad hoc leaves at once when the others are gone unless it escalated (>1 other ever) or is a channel's. Dialog: surface 45% x 27%, title largest bold one line, large progress bar, large buttons at the end, Leave now brand background.
- Call title (useMeetingTitle + callTitleService.getDefaultCallTitle; enableTitleFetchForAllCalls on for Rooms): meeting chat topic; channel 'Meeting in "{name}"'; group chat "Call with {topic}"; no topic: meeting "Microsoft Teams meeting", else others' names (sorted, 3 max, "{first} and N others").

- 2026-11-19 built: room_mode::call_title (Teams Rooms' title rule) shown once the room accepts (window title; the ringing console keeps the inviter); ad-hoc escalation (no instant leave once >1 other was in); end time from the meeting chat's meeting property (0001-01-01 ignored); channel threads wait for the end; RoomAutoExit with Rooms' strings and layout; harness --rooms-meeting, --room-exit-shot, ROOMEXIT lines.
- Live (linuxlt, btvirt radio; ost-test1 inviting OST Test Room from Nearby): scheduled "OST TEST 226 room 02:12" (3 min) -> room auto-accepted, title "OST TEST 226 room 02:12 | OST" (was the inviter's name); the inviter left; end 10:15:59, ROOMEXIT shown 10:20:59 (300 s), "About to leave meeting ..." with Snooze / Leave now, bar full and left 10:21:14 (15 s); call ended in the room's log; event deleted. Channel Meet now (OST layout test): the room can't read the channel thread (403), so its title is "Microsoft Teams meeting", as Teams Rooms' fallback; meeting ended by the inviter, room's call ended.
<!-- SECTION:NOTES:END -->
