---
id: TASK-0036
title: 'Desktop: video in meetings and in calls OST places'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-06T16:10:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Incoming 1:1 calls carry video both ways. Calls OST places offer video but Teams web answers audio-only (acceptedCallModalities [audio], video m-line rejected); meetings need video subscription with the media processor. The pre-join camera stays off until this works.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a call OST places, the callee's camera shows in OST and OST's camera in Teams
- [ ] #2 In a meeting, participants' video shows on their tiles and OST's camera reaches them
- [ ] #3 Pre-join's camera switch works
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Calls: offer and answer the camera line receive-only while the camera is off (as Teams does), and turn it on/off with a re-offer through the same machinery as Share.
2. Placed calls: offer in Teams' NGC content type so Teams accepts the video line.
3. Meetings: subscribe to participants' video with the media processor; send ours.
4. Pre-join camera switch.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Placed calls: with the offer in application/sdp-ngc-1.0, Teams accepts OST's video line. Randy's camera showed in OST in a call OST placed (accepted with video).
- The camera line now sends only while the camera is on: offered/answered recvonly (or inactive) otherwise, and Camera on/off is a re-offer (Reoffer::Camera) answered and acknowledged like Share's. Before, Teams showed OST's tile as an empty video instead of the avatar.
- Live: OST placed a call with --camera-on (Randy accepted with audio): the re-offer was taken and OST's camera showed in Teams web. Same for a call Randy placed to OST.
- One webcam on this machine: Chrome and OST can't both hold it, so each direction was tested in its own call.
<!-- SECTION:NOTES:END -->
