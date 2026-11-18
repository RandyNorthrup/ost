---
id: TASK-0161
title: Room audio with the tenant's Teams Rooms (search, Nearby, add the room)
status: To Do
assignee: []
created_date: '2026-11-15T20:59:00Z'
updated_date: '2026-11-18T04:06:00Z'
labels:
  - calls
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' pre-join Room audio also finds the tenant's Teams Rooms: 'Search for a room' searches them, 'Other Suggestions' lists suggested rooms, 'Nearby' lists rooms found over Bluetooth/ultrasound (with Teams' Bluetooth and microphone hints), and joining adds the chosen room's audio system to the meeting. OST's picker (TASK-0159) has the connected room devices only; the test tenant has no Teams Room resource yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Typing in Room audio's picker finds the tenant's rooms as Teams does
- [ ] #2 Other Suggestions and Nearby list rooms as Teams does, with Teams' hints
- [ ] #3 Joining with a tenant room adds the room to the meeting as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 tenant (user: "you are authorized to adjust anything in the test tenant to unblock us"): room mailbox 'OST Test Room' (ost-test-room@scnetsolutions.com, capacity 6, location 'OST lab') created, so room search, suggestions and adding a room to a meeting can be tested. A Teams Rooms device (proximity join) is still absent.

Built so far: Room audio's picker (search box, Connected room devices, Other Suggestions) from TASK-0159. Missing: searching the tenant's rooms, Nearby, adding the room to the meeting. (Audit 2026-11-16)

2026-11-17 (agent):
- Teams (bundles 81744/89637/911361, captured on winpc 2026-11-17 via CDP): Other Suggestions = POST https://outlook.office.com/SchedulingB2/api/v1.0/me/findmeetinglocations {MaxCandidates:10, ConferenceRoomsOnly:true}; search adds QueryConstraint {Query} and LocationProvider '80'; each LocationEmailAddress resolved via MT fetchShortProfile?isMailAddress=true (MRI = room id). Teams on winpc: suggestions empty ('Unable to find any rooms'), search 'OST' -> 'OST Test Room / Offline'. Nearby = BLE manufacturer data 0x0006 '34 F0 00 <packed object id> <code BE> <type>' (-75 dBm list, -50 adjacent). Join with a room: computer audio off, then addRoomParticipant = POST addParticipantAndModality with participantInvitationData.invitationData {proximitySource 1, deviceType 'computer', autoAcceptAuthorization {token: code}|null, meetingInfo}.
- Tenant: OST Test Room's account was already enabled; bought Microsoft Teams Rooms Basic (free, $0.00, 3-year term Nov 18 2026 - Nov 17 2029, renews at $0, billing profile Visa 9604) and assigned it to OST Test Room.
- OST: api::rooms (findmeetinglocations, resolve, beacon parser), desktop room_ble (BlueZ LE scan), backend tenant_rooms / nearby_rooms / add_room_to_meeting, OutgoingCall::add_room, PreJoin picker sections (Nearby, Other Suggestions, search), Teams' hints, harness --rooms-test. Emulated Teams Rooms beacon: scratchpad hid/mtr-beacon.sh (bluetoothctl on this PC).
- Live (linuxlt, ost-test1): search 'OST' -> OST Test Room (Offline), as Teams; Nearby -> OST Test Room from the emulated beacon (-35 dBm, adjacent); joining a Meet now in OST layout test with the room: invitation accepted by the conversation (202), then addParticipantFailure 'The user is unavailable at the moment' because no endpoint is signed in as the room.
- Open: the room joining needs an endpoint signed in as ost-test-room (a Teams Rooms device, or OST signed in as the room: a password sign-in the user has to do); ultrasound room detection (Teams' native DSP) not implemented.
<!-- SECTION:NOTES:END -->
