---
id: TASK-0273
title: Control Room System on a room's menu as Teams
status: In Progress
assignee:
  - '@crsZ'
created_date: '2026-11-24T09:17:00Z'
updated_date: '2026-11-24T10:21:00Z'
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
<!-- SECTION:NOTES:END -->
