---
id: TASK-0278
title: Video tile menu, room captions and room remote strings as Teams
status: In Progress
assignee:
  - '@tilB'
created_date: '2026-11-24T15:00:00Z'
updated_date: '2026-11-24T17:40:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0273: Teams has a ··· menu on video tiles (one of the places it offers Control Room System), OST has none; an OST room invited into a meeting can't run captions, so its remote has no Captions; the room remote's strings come from Teams' extensibility app, which OST's runtime string table doesn't fetch, so they stay English.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Video tiles have Teams' ··· menu with Teams' items for each kind of participant, each working as in Teams
- [x] #2 An OST room invited into a meeting runs captions as a Teams Room does, and its remote offers Captions
- [ ] #3 The room remote's strings are translated from Teams' extensibility app strings, fetched at runtime like the others
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (agent tilB) research, Teams 26304 bundles: the video tile ··· menu is CallingParticipantContextMenu (879019 getMoreMenuItems; Remove/role changes are not in it, People pane only) and your own tile's MyselfVideo menu (846553 renderMoreMenu: Switch camera, Pin for me, Hide me, Remove/Include me in gallery, Spotlight, Edit display name, Lower my hand, Fit/Fill). Spotlight asks first (634992, the roster uses the same dialog). The room remote's strings are the extensibility apps' main-locale-<lang> chunk (namespace extensibilityRoomRemote, plain keys), named by the app's main bundle (teams.microsoft.com/extensibility-apps/roomremote/).
- Measured on winpc (Teams as organizer, meeting OST TEST 278 tile menu + a cast): OST Test 3 (presenter, video, muted): Mute participant (disabled), Pin for me, Spotlight for everyone, Fit to frame, divider, Report; with a raised hand Lower hand after Mute; OST Test Room: Mute participant, Pin for me, Spotlight for everyone, Control Room System, divider, Report; your tile: Pin for me, Hide me, Remove me from gallery, Spotlight for everyone (195.08 wide). Menu 2 px in, radius 4, items 177.88 x 32 2 apart, label at 30; other's menu after-bottom of the ···, yours above-start; right-click opens it at the pointer. ··· 20 x 24 in the name tag 4 after the last glyph (16 px glyph for others, 20 for you), brand while open. Spotlight dialog 600 x 152.67. Fit to frame keeps the tile's light background around the picture.
- linuxlt crashed/rebooted at ~15:33 during the first build (my room + test3 died with it, no clean leave possible).

- Built (commit 97753ae5 on the agent branch): VideoTileMenu.qml (Teams' items per participant and role, ··· in the name tag on hover, right-click at the pointer, after-bottom / above-start placement with flips, spotlight confirmation also from the People pane), MeetingTile ··· + Fit to frame (tile background around the picture), self pin in the pin area, Lower hand = removeState of their raiseHands state. Room captions: the attach's join answer (additionalActionResponses[0].output) gives the answered call its conversation links; recorder::Tracker (shared with OutgoingCall) follows the recorder; captions invite the recorder, StartCaptions, PUT transcriptionPrefs; an answered call resets captions/recorder state. Room remote strings: x.roomremote (extensibility apps main-locale-<lang>, found from the app page), RoomRemotePane strings pinned to its ids; ids/teams_resources regenerated.
- Live (Teams on winpc -> OST Test Room cast): Teams' Room Remote now shows Captions; Captions on -> the room invited the recorder (202), StartCaptions 200, captions running; the room window showed live captions of its speech (Piper speech on a virtual mic); the remote showed Captions on; Captions off; Disconnect room -> Call end 202.
- Live (OST ost-test1 controller, relayed beacon): tile menus room/you/right-click, Fit/Fill, pin/unpin (theirs and yours), Hide me, spotlight ask + spotlight + stop; Control Room System from the room's tile -> remote with Captions; captionsOn -> recorder + captions; second meeting with the same room started captions again (after the reset fix).
- Live (meeting OST TEST 278 tile menu, ost-test1 organizer with OST Test 3): OST's menu for Test 3 = Teams' exactly (Mute participant disabled, Lower hand, Pin for me, Spotlight for everyone, Fit to frame, divider, Report); Lower hand lowered Test 3's hand; spotlight applied and stopped; Teams' People pane Spotlight asks the same dialog.
- Live (meeting OST TEST 278 attendee view, Test 3 organizer, ost-test1 made attendee): Teams: others Pin for me, Fit/Fill, divider, Report; yours Pin for me, Hide me (min width 138); OST the same after the overlay/min-width fixes.
- Not live: a guest's tile (Teams' menu code has no guest branch; the old guest join tool is gone), and OST running in another language showing the remote's fetched strings (de-de chunk fetched and parsed at generation: Controlling -> Steuerung).
- Tests: lib 965 passed, desktop 37 passed.
- Cleanup: every OST instance left its call (hung up / Call end 202 in its log) before it stopped; room, relay, btvirt, virtual mic and camera feeds stopped (hci0 advertising 0); test meetings deleted; linuxlt helper files removed (v4l2loopback test cameras reloaded after the crash, left loaded as before). winpc: Teams ost-test1 on Calendar, in no call, Cast closed; test window, scheduled task and script removed.
<!-- SECTION:NOTES:END -->
