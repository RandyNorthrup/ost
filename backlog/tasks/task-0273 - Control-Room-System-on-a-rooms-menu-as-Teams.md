---
id: TASK-0273
title: Control Room System on a room's menu as Teams
status: In Progress
assignee:
  - '@crsZ'
created_date: '2026-11-24T09:17:00Z'
updated_date: '2026-11-24T13:01:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0270: Teams' ··· menu on a Teams Room participant in a meeting has Control Room System; OST lacks it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A room participant's ··· menu offers Control Room System where Teams does, and it controls the room as Teams does, verified with OST Test Room
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
<!-- SECTION:NOTES:END -->
