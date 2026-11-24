---
id: TASK-0273
title: Control Room System on a room's menu as Teams
status: Done
assignee:
  - '@crsZ'
created_date: '2026-11-24T09:17:00Z'
updated_date: '2026-11-24T15:00:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0270: Teams' ··· menu on a Teams Room participant in a meeting has Control Room System; OST lacks it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A room participant's ··· menu offers Control Room System where Teams does, and it controls the room as Teams does, verified with OST Test Room
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (agent crsZ) research, Teams 26304 bundles (room-remote chunk, 527114 RemoteControllerSessionManager / RemoteControllerConnectionHandler / RemoteControllerIncomingCommandFactory / RemoteControllerCallState, 879019 participant menu, calling-roster) + SlimCoreWebview2.dll BTT sessions (Ghidra) + the extensibility app at teams.microsoft.com/extensibility-apps/roomremote (room-remote-app chunk, extensibilityRoomRemote strings):
  - Menu: Control Room System shows when ECS calling.enableRoomRemoteDesktop, client Desktop, call not P2P, participant deviceType Room (roster and video tile menu).
  - Click: side panel "Room Remote" (spinner) -> createRoomRemoteSession: BLE checkRoomProximity (beacon of that room MRI, its proximity code = salt; 30 s ECS) -> SlimCore BTT session: POST api.cc.skype.com cc/v1/sessions {sessionInvitation {from, to, sessionType roomControls, links {acceptance, rejection, receive, end}}, debugContent, registrationId, command sessionStart, commandDetails {meetingInfo {threadId}}}; the room gets calling push evt 122 {sessionNotification {from, to, links {accept, reject}}, registrationId (controller endpoint), command sessionStart, commandDetails} and Teams Rooms accepts only for its active call's thread (sessionAcceptance {links {receive, end}}) -> pair {salt, sessionId, controllerEndpointInfo, meetingInfo} -> room checks the salt and answers {accepted, roomEndpointInfo, supportedCapabilities {mediaControls, stageLayoutControls, meetingControls}, initialState {toggleMute, toggleCamera, toggleCaptions, stageLayout}}.
  - Commands: mute/unmute, cameraOn/Off, captionsOn/Off, volumeUp/Down (steps of 10, min 1 mutes the speaker), showVideoGallery/showContent/showVideoGalleryAndContent/showLargeGallery/showTogether/showFrontRow/..., leaveMeeting (room unpairs, leaves; remote shows Disconnected / The room has left the meeting / Ok). Room pushes stateUpdate / capabilityUpdate.
  - Remote UI (app): Controlling + room name; Mic on/off, Video on/off, Captions on/off; Layout (menu of the room's layouts); volume down / speaker / volume up; Disconnect room. Errors: Room not detected, Connection failed, Error (Unable to perform action), Disconnected; Retry / Cancel.
- Live 1 (winpc Teams cast to OST Test Room, then the room's People row ··· > Control Room System): the room's Trouter got evt 122 exactly as above; OST ignored it, Teams kept the Room Remote spinner (4+ min; its 45 s ECS timer is cleared on the loading re-render).

- 2026-11-24 live protocol (winpc Teams -> OST Test Room, rounds 2-6): the call controller relays the session. Room accepts with POST <accept> {debugContent, registrationId (its calling endpoint), sessionAcceptance {links {receive, end}}}; its links must be on the socket's service front (-f host, :3443) since the CC posts to them; the reply is {sessionAcceptanceResponse {links {broadcast, session}}} (cc/v1/activeSession/...). Teams then sends pair through the CC to the room's receive link as {registrationId, command, commandSequenceNumber, commandDetails (object), debugContent {causeId, chainId = Teams' session id}}; pair details {causeId, commandName, companionResponseRequired, controllerEndpointInfo {clientType default, clientVersion, deviceName, endpointId}, meetingInfo {threadId}, salt [beacon code], sequenceNumber, sessionId, targetEndpointId}; commands {callId, companionResponseRequired true, conversationId, endpointId "", targetEndpointId}. The room answers `response` {..., requestCauseId = the command's debugContent.causeId, statusCode 200} the same way through its relay links. Teams answers our stateUpdate with response {companionResponseRequired false, requestCauseId, salt [], statusCode 200, targetEndpointId}.
- Teams quirk: every other Control Room System click hangs on the spinner (its session map keeps the previous session); closing the panel and clicking again works.
- Verified (round 6): Teams' remote showed "Controlling / OST Test Room", Video off (greyed, room without camera), Mic on, Captions off, Layout, volume box, Disconnect room; Mic -> room muted, the remote showed Mic off via stateUpdate, Mic again -> unmuted; Captions -> captionsOn reached the room (OST can't caption a meeting it was invited into: capability now off); volume down/up -> room speaker 100 -> 90 -> 100; Layout -> Gallery (showVideoGallery); Disconnect room -> the room unpaired and left (Call end 202), Teams closed the panel (no dialog).
- Measured Teams' remote (iframe 319.33 x 471.33, 21 in): Controlling 12/16 semibold at (16, 23.6), name 16/22 semibold; glyph buttons 32 x 31.33 at y 61.1 (centres 40.7 / 140.5 / 240.3), labels 14/20 semibold at 107.4 (Captions wraps); Layout glyph at 209.3, label 255.7; volume box 16 in, 52.67 tall, 0.67 #424242, radius 2, buttons at 53 from each end; Disconnect room 120 x 40 at 420.8, white, 0.67 #D1D1D1, 12/16; glyphs are Fluent filled icons drawn from the 2..18 window of the 20 grid.

- 2026-11-24 OST as controller (ost-test1 spatest on linuxlt hearing OST Test Room's beacon relayed to btvirt hci1/hci2; --room-remote-test: Meet now, room added with its code, People ▸ room ··· ▸ Control Room System): the menu lists Mute participant / Pin for me / Spotlight for everyone / Control Room System / Make an attendee / Remove from meeting / Report as Teams; spinner pane; session started (sessionInvitationResponse {links {outgoingSession}}), acceptance pushed to our acceptance link {registrationId, sessionInvitationAcceptance {links {broadcast, session}}}; a pair POSTed to the activeSession `session` link was taken (202) and went nowhere, to `broadcast` it reached the room: messages go to broadcast both ways. Paired; mute -> room muted, stateUpdate showed it; unmute; volume down/up (100 -> 90 -> 100); Gallery; Disconnect room -> the room unpaired and left (Call end 202), the pane closed; Close -> session ended: POST to the session link did nothing, DELETE on it reached the room's end link (as Teams' close did).
- Tests (linuxlt): lib 957 passed, desktop 37 passed. Commit a76be13e.
- Cleanup: every controller run left its call (hung up the call leg + CAST done) and exited by itself; each room run left by itself (Call end 202) before it was stopped; relay stopped, btvirt pair down, hci0 advertising 0; dumps, shots and binary copies removed. winpc: Teams ost-test1 on Calendar in no call, Cast closed; test window closed, its script and scheduled task removed; no diagnostic file was made.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Control Room System now works as it does in Teams, from both ends. It was verified live against OST Test Room with Teams on winpc and with OST as the controller.

What Teams does (read from its bundles and SlimCore, then confirmed live):
- Where it shows: a Teams Room's ··· menu in a meeting. Conditions: ECS calling.enableRoomRemoteDesktop, a desktop client, not a 1:1 call.
- Clicking it opens a "Room Remote" side panel with a spinner.
- Teams scans for the room's Bluetooth beacon and uses its proximity code as the salt.
- It then starts a Better Together session: POST cc/v1/sessions with sessionType roomControls. The room's endpoints get calling push 122. A room in that meeting accepts with its receive/end links.
- Pairing: Teams pairs with the salt. The room answers with its name, its controls and its state.
- Remote panel: Controlling + room name; Video / Mic / Captions; Layout (a menu of the room's layouts); a volume box (down / speaker / up); Disconnect room.
- Commands: mute/unmute, cameraOn/Off, captionsOn/Off, volumeUp/Down (steps of 10), layouts, leaveMeeting. The room sends stateUpdate/capabilityUpdate back.
- Transport: everything goes through the call controller. Each side posts to the active session's `broadcast` link, which relays to the other side's `receive` link. DELETE on the session link ends it.

Changes (commit a76be13e):
- Engine `api::room_remote`:
  - Session push parsing.
  - Invitation, acceptance, message and end bodies.
  - Active-session links.
  - Room state and capabilities, with capability updates.
  - The pair answer.
  - Volume steps.
- Trouter:
  - Session links (bettertogether/session/<id>/...) are acknowledged at once and published as EventKind::RoomRemote.
  - Session commands on the BTT path are kept out of phone pairing.
- Room side (room mode):
  - Accepts only for the meeting it is in and checks the beacon salt.
  - Works mic, camera, captions, volume, layouts and leave through the room's own controls.
  - Pushes state and capability changes.
  - Captions are offered only when the room's call can caption.
- Controller side:
  - People pane ··· ▸ Control Room System, in Teams' menu order.
  - RoomRemotePane, measured against Teams' remote: layout, sizes, colours and the remote's cropped Fluent glyphs. Also Teams' spinner and its error dialogs (Room not detected, Connection failed, Error; Retry / Cancel).
  - Room disconnect or unpair closes the pane. Close or leaving the call ends the session.
- Harness: --room-remote-test, --cast-room-remote, --cast-rr-leave.
- i18n ids regenerated.

Verified live:
- Teams on winpc → OST Test Room:
  - The remote showed the room.
  - Mic toggled, captions request arrived, volume 100→90→100, Gallery.
  - Disconnect room made the room leave, and Teams closed the panel.
- OST (ost-test1) → OST Test Room:
  - Menu, spinner, pairing, mute/unmute shown back through stateUpdate, volume, Gallery.
  - Disconnect room made the room leave and the pane close.
  - Close ended the session on the room.

Tests: lib 957 passed, desktop 37 passed.

Open:
- OST has no video-tile ··· menu, where Teams also offers the item.
- An OST room invited into a meeting can't run captions, so it doesn't offer them.
- The remote's strings come from Teams' extensibility app namespace, which OST's string table lacks, so they stay untranslated.
- Teams' own quirk: every other Control Room System click hangs on the spinner. Not copied.
<!-- SECTION:FINAL_SUMMARY:END -->
