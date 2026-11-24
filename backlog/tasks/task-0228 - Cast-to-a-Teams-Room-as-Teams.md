---
id: TASK-0228
title: Cast to a Teams Room as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-20T01:10:00Z'
updated_date: '2026-11-24T06:58:00Z'
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
- [x] #1 Cast finds the nearby Teams Room as Teams does
- [x] #2 Casting to the room shows the content on the room as Teams does, verified live with OST in room mode and against Teams
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

Built so far: the Cast wizard (rooms with presence and nearby mark, meetings, content), Teams' cast flow (join with devices off, start sharing, invite the room with the nearby-room invite), and the room joining PowerPoint Live and Whiteboard sessions it hears of. Verified live with OST in room mode: Just cast and Cast and join both showed the deck on the room. Missing: side-by-side comparison with Teams on winpc (colours of the wizard not measured), casting a screen or window (the KDE picker on linuxlt can't be driven), and the room staying in an empty Meet now when the laptop leaves.

- 2026-11-20 (agent cast-finish) progress: Teams on winpc Cast window measured (Settings and more > Cast): 626x713 CSS, dark even with Teams in light theme (cast app isThemePinnedToDarkOrHighContrast), band #292929 60 tall, tile #4F52B2 radius 3 (OST had 4, fixed), "Didn't find any Teams Rooms nearby that we can cast to." at y 141, Next 96x32 disabled #1F1F1F/#5C5C5C.
- Teams Rooms 26198 auto exit read again (449162 handleEventChanges): no cast rule and no channel rule; ad hoc = meetingType "Adhoc" exactly (a Meet now is "MeetNow"); in-call = everyone connected but calling bots and the room's own endpoints. OST: channel exemption dropped, phone/guest participants count (bots 28: excluded).
- Screen/window cast: OST_SCREENCAST_RESTORE=<file> (persist mode 2 + restore token, new token kept). KDE restores a window by app id + title; a token for the test window is seeded in the portal permission store (linuxlt ~/cast228/seed seedcast).

- Proximity on winpc: Teams on winpc never listed the room. A WinRT BLE watcher on winpc (C# blewatch, 15-30 s) heard other devices at -84..-99 dBm but not the room's beacon from linuxlt hci0 (btmon: legacy ADV_NONCONN_IND, 1.28 s, 0 dBm, Microsoft 0x0006 34F000<oid><code>), nor the same beacon relayed from this PC's radio; a beacon published from winpc itself isn't heard by its own scanner. Teams lists rooms at -75 dBm or better, so Teams on winpc needs a radio near it; none of ours is. Cast's room list is only the native BLE nearbyRooms subscription (no search, no recent rooms).
- Teams' Cast window measured again (searching / none found) in light and in dark: identical apart from the html theme class (theme pinned dark).
- Live (linuxlt, btvirt hci1 room / hci2 laptop): window cast with OST_SCREENCAST_RESTORE: no picker, KDE restored "OST cast test window" (968x572), sharer 202, room auto-accepted. Found: the room's stage stayed empty: the processor's invite is a meeting offer (camera + 9 receive slots + applicationsharing-video + data) but the room answered it as a 1:1 call (no slots, no control plane), and the roster only fed show_share/show_videos to outgoing calls. Fixing: incoming meeting offers answered as a meeting join (MidMap, answer_sdp_meeting), ActiveCall show_videos/show_share/control_video.
- Just cast Meet now to the room: meetingType MeetNow, endTime not valid -> not ad hoc; the laptop left (plain leave) and the room stayed alone, as Teams Rooms 26198 (no cast or end rule applies); left with its Leave button (Call end 202).

- 2026-11-20 room fixed: the meeting's invitation is now answered as a meeting join (src/calling/incoming.rs answer_meeting_offer: MidMap, answer_sdp_meeting, clientContentForMediaController; the sharing line answered to the offered direction: send-only -> receive-only, which the processor needs: answered sendrecv it never ran ICE). ActiveCall show_videos/show_share/control_video; the roster and video control requests reach an answered meeting call too.
- Live (cast c6, linuxlt btvirt): Just cast with Window, the portal restored "OST cast test window" with no picker (OST_SCREENCAST_RESTORE), the room auto-accepted, "answering the meeting's invitation as a meeting slots=9 share=true", ICE connected, control plane open, decoded the 968x572 share and showed the test window (clock running) on its stage; --cast-end ended it, the room's call ended.
- Item 3 verified: Just cast is a Meet now (meetingType MeetNow, endTime 0001-01-01T00:00:00 from the room's meeting details): Teams Rooms 26198 neither treats it as ad hoc nor ever reaches its end, so the room stays after a plain leave (c1, as Teams Rooms); a channel Meet now (Adhoc) is left at once now (j3: "leaving ad-hoc call because no other participants left", Call end 202), as Teams Rooms has no channel rule.
- Open: the laptop doesn't get the room's camera in a meeting the room was invited into (the processor never asks for it; no media description sent from an answered call).
- Tests: 809 lib tests pass (linuxlt). Cleanup: room and test window stopped, btvirt pair down, restore token deleted from the portal store, trouter dumps and pcap removed; winpc: Teams back on Chat, theme back to Follow OS, helper files and task removed.

- 2026-11-20 winpc Bluetooth (linuxlt 3 ft away): linuxlt hci0 is the real Realtek radio (USB, HCI 5.1), not a virtual one; its room beacon was legacy ADV_NONCONN_IND, 0 dBm, non-resolvable random address, the same type and address kind as Windows' own Microsoft (0x0006) beacons that winpc does receive. Plain test adverts from linuxlt hci0 (OSTTEST non-connectable, OSTTESTC connectable on the public address) were heard by this PC but never by winpc's watcher (active scan, ssh session and interactive session alike). A Windows beacon nearby (2C:AC:1D:90:C7:85) reads -41 dBm at linuxlt and -82 dBm at winpc; an advert published from winpc (0xFFFF test data, status Started) was heard by neither linuxlt nor this PC. winpc's Intel AX201 Bluetooth (8087:0026, driver 23.40, LE/central/extended advertising supported) is on; its Wi-Fi side reads 99%. So winpc's Bluetooth radio path is about 40 dB down in both directions: an antenna/hardware problem, not a Windows setting or a beacon format. Teams on winpc can't list any room until that is fixed (antenna leads on the AX201, or a USB Bluetooth adapter). All winpc helpers, tasks and linuxlt test adverts removed.

Built so far: the Cast wizard and Teams' cast flow; the room accepts and shows a cast window or PowerPoint Live (verified live with OST in room mode, including casting a window via the portal's restore token); the room's auto-exit matches Teams Rooms. Missing: Teams' own Cast to the room live on winpc — winpc's Bluetooth radio is about 40 dB weak in both directions (likely an antenna lead), so it never hears the room's beacon; needs the antenna reseated or a USB Bluetooth adapter.

- 2026-11-22 (agent wifiM) winpc Bluetooth, software side (no hardware bought or moved):
  - Driver: AX201 Bluetooth (USB 8087:0026) was on Intel 23.40.0.2 (Feb 2024); Windows Update offered no Bluetooth driver. Installed Intel's current package BT 24.80.0 (driver 24.80.0.2, ibtusb.sys 24.40.13.1; from downloadmirror.intel.com, SHA512 = Intel's page, Intel-signed), only the AX201 INF, with pnputil /add-driver /install (oem186.inf). Windows registered it but needs a reboot to load it ("pending system reboot"; restart-device refused). Not rebooted (no auto-logon, someone has to sign in at the console); it loads at winpc's next restart.
  - Power saving: USB selective suspend for the radio turned off (Enum\USB\VID_8087&PID_0026\...\Device Parameters DeviceSelectiveSuspended 1 -> 0; applies at the same restart). The device has no "allow the computer to turn off" entry; the power plan's USB selective suspend is already off on AC.
  - Coexistence: the AX201's Wi-Fi side is not connected (winpc is on Ethernet), so there is no Wi-Fi traffic competing with Bluetooth; the driver offers no Bluetooth collaboration setting (Wi-Fi transmit power already Highest).
  - linuxlt beacon: the Realtek controller (hci0, HCI 5.1, extended advertising, LEAdvertisingManager CanSetTxPower, range -20..+22 reported) always selects 0 dBm for advertising: asked for +20 dBm through BlueZ TxPower it answered "TX power (selected): 0 dBm" (btmon). The advertising interval can be shortened from BlueZ's 1280 ms to 100 ms (MinInterval/MaxInterval).
  - Measured from winpc (WinRT BLE watcher over ssh, active scan, 30 s): linuxlt test beacon (legacy ADV_NONCONN_IND, 0 dBm, 100 ms) heard 4 times out of ~300 at -104..-106 dBm (before: never heard at 1280 ms). For comparison the strongest other beacons at winpc read -84..-95 dBm. Teams lists a room only at -75 dBm or better: ~30 dB short, which a driver update is very unlikely to close.
  - Left for the user: Teams' own Cast to the room on winpc needs a working radio near winpc (AX201 antenna leads reseated, or a USB Bluetooth adapter). Then run Settings and more > Cast on winpc with OST in room mode on linuxlt and compare with OST's Cast. Left in place: BT driver 24.80 pending restart and selective suspend off on winpc (to undo: roll back to oem150.inf 23.40.0.2 and set DeviceSelectiveSuspended 1).

- 2026-11-23 (agent castT) winpc TP-Link Bluetooth (USB 2357:0604, TP-Link driver 1.9.1038.3023) is the active radio; the AX201 shows code 31 (its staged Intel 24.80 driver still waits for a reboot), left as it is, nothing disabled. winpc now hears nearby beacons at -20..-60 dBm.
- linuxlt hci0 transmits fine (BlueZ extended-advertising set, legacy ADV_NONCONN_IND): the -104 dBm of 11-22 was winpc's AX201. A WinRT watcher started after the beacon sometimes reports nothing for a while; started first it hears it at once. OST Test Room's beacon (room mode, hci0) read -62..-64 dBm at winpc (Teams needs -75 or better).
- The room profile's 24 h browser sign-in had lapsed (AADSTS700084 / AADSTS50058): signed in again through OST's sign-in page over CDP (account tile + password from creds.md, never printed).
- Teams' own Cast on winpc, live: Settings and more > Cast listed "OST Test Room / Available" (picked by itself), no meetings step, content step = "Share content" card (Include sound, Screen, Window (6); no PowerPoint Live without recent files), Window > "OST cast test window" (a WinForms test window, never the desktop) > Cast. Teams made a Meet now titled "OST Test Room", joined muted with the camera off, shared the window and invited the room (invitationData proximitySource 1, deviceType computer, autoAcceptAuthorization = the beacon code). The room (OST, linuxlt) auto-accepted (source Bluetooth, in tenant), answered as a meeting (slots 9, share), decoded the 956x566 share and showed the test window with its clock running. Teams kept the Cast window open; its meeting window showed a "Joined in room" callout and People nesting OST Test 1 under the room (follow-up TASK-0268); Leave asked "You're currently sharing. Are you sure you want to leave?".
- After Teams left, the room stayed alone, then left by itself 5 min 15 s later (ROOMEXIT shown 04:18:18, Call end 202): Teams' Just cast updates the Meet now's chat (instantMeetingService.updateInstantMeetingInfo: subject, meetingType MeetNow, startTime = endTime = now), so Teams Rooms' auto exit applies. OST's own cast left the chat's times at 0001-01-01, so the room would never leave: fixed (below).
- Invitation diff, Teams vs OST cast (room's trouter dump): identical apart from languageId (Teams "en-us", OST "en-US") and key order.

- Fixed after the side by side (castT):
  - Just cast / Meet now: OST now updates the new Meet now's chat as Teams' instantMeetingService.updateInstantMeetingInfo does (topic, then PUT threads/{id}/properties?name=meeting with subject, meetingType MeetNow and, when the meeting is started rather than only linked, startTime = endTime = now). Calendar Start meeting / Get a link to share pass start true / false. Live (cast2): the room read meeting_end 05:04:49.030Z, the caster left at 05:05:58, the room's auto exit showed at 05:10:59 and it left at 05:11:15 (Call end 202), as with Teams' cast.
  - Cast window: Teams leaves it open on its last step after Cast (its wizard only fires the calling intent); OST now does the same (harness uses castWindow.started).
  - Room cards as Teams' (measured): #242424 card, picked one with the 2 px white focus ring, TV glyph (Teams' TvIcon = tv-20) in a 44 px #666666 avatar 20 in, header 14 regular at 79, presence 10 px near white under it, nearby glyph only when the room is adjacent (Teams' isNearby = isAdjacent; OST showed it whenever a code was heard), check 19 from the end.
  - Content step as Teams' Cast tray: a 448-wide #292929 card (radius 4), "Share content" (16 bold) with Include sound (12) and its switch, Screen / Window over 144 x 80 tiles 24 apart, PowerPoint Live only when there are recent files (Teams showed none for ost-test1).
  - Leave while sharing: Teams' hang-up speed bump (ECS enableHangupSpeedbumpMode "Always") always asks "You're currently sharing. Are you sure you want to leave?" while you share; OST only asked when the Settings option was on.
- Live OST cast (cast2, ost-test1 spatest on linuxlt hearing the room's beacon relayed to btvirt hci1/hci2 while the room advertised on hci0 for winpc): Cast listed OST Test Room, content = Window restored by the portal token (no picker; seeded for the Tk window's X11 class "Ostcasttest"), Meet now "OST Test Room" joined muted with the camera off, window shared (968x572), room added with the live code (202); the room auto-accepted (Bluetooth, in tenant) and showed the test window with its clock running. Invitation identical to Teams' apart from languageId casing.

- Step 4, one room in both Cast lists at once (05:23 UTC): Teams on winpc listed "OST Test Room / Available" (TP-Link radio, beacon from linuxlt hci0) while OST (spatest on linuxlt, the same beacon relayed to btvirt hci1/hci2) listed it too (code, rssi -60 assumed on the virtual radio). Teams then cast to it again (05:24): room auto-accepted, showed the window, left by itself 5 min after Teams left (05:33).
- Card border: with no keyboard focus, Teams' picked room card has only its #0F0F0F hairline (the white ring of the first run was focus), now as in OST.
- Left as is: Teams' cast joins with the mic muted but usable; OST's cast uses its "Don't use audio" state (mic greyed). Both send the same streams to the meeting (audio sendrecv muted, video recvonly, sharing sendonly, data).
- Tests: cargo test --features audio,video --lib 944 passed; desktop tests passed.
- Cleanup: every OST cast run left its call (CAST done + call ended in its log) before it was stopped; the room left each meeting by itself (Call end 202) and was then stopped, so its beacon is gone (hci0 ActiveInstances 0); relay and btvirt pair stopped; test windows closed; portal restore tokens deleted; trouter dumps deleted; winpc: Teams on Calendar (Today) in no call, Cast window closed, helper files and scheduled task removed. Meet nows aren't calendar events (Cast's meetings step listed none), so there were no test meetings to delete.
- winpc devices: nothing changed in this session. The TP-Link (USB 2357:0604, TP-Link driver 1.9.1038.3023) is the active radio; the AX201 shows code 31 because its staged Intel 24.80 driver still waits for a reboot. It was not disabled.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cast to a Teams Room now matches Teams' own Cast, verified live side by side: Teams desktop on winpc and OST on linuxlt both cast to OST Test Room (OST in room mode on linuxlt), and each run was compared with the other.

What was verified live:
- Proximity: winpc's new TP-Link adapter hears the room's beacon from linuxlt hci0 at -62..-64 dBm (Teams lists rooms at -75 or better). The old AX201 heard it at -104.
- Teams to room: Settings and more > Cast listed OST Test Room; Window > test window > Cast. The room auto-accepted (Bluetooth, in tenant) and showed the window.
- OST to room: the same flow, with the window restored by the portal token. The room auto-accepted and showed the window.
- The invitations are identical (proximitySource 1, deviceType computer, autoAcceptAuthorization = beacon code), apart from languageId casing.
- Both apps listed the same room at the same time.
- After the caster leaves, the room leaves on its own about 5 min later in both cases.

Changes (commit 4239a4b4):
- Just cast / calendar Meet now update the meeting chat as Teams' updateInstantMeetingInfo does: topic, plus meeting property with startTime = endTime = now when started. Without this the room never left an OST cast.
- The Cast window stays open on its last step after Cast, as in Teams.
- Room cards and the content step are restyled from measurements of Teams. The nearby glyph now shows only for adjacent rooms. The content step is a "Share content" card, and PowerPoint Live shows only when there are recent files.
- Leaving while sharing always asks first ("You're currently sharing. Are you sure you want to leave?"), as Teams' hang-up speed bump does.

Tests: lib 944 passed (new: instant_meeting_property_is_teams_update); desktop tests passed.

Open:
- OST's cast greys the mic out (its no-audio state). Teams keeps it muted but usable. The streams sent are identical.
- untranslated.txt / ids.json not regenerated for the new strings.
<!-- SECTION:FINAL_SUMMARY:END -->
