---
id: TASK-0235
title: 'Room mode: the room''s camera seen by others in an invited meeting'
status: Done
assignee: []
created_date: '2026-11-20T08:37:00Z'
updated_date: '2026-11-21T00:03:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0228: when OST in room mode is invited into a meeting, it sends video but the meeting server never asks for it, so the laptop and others don't see the room's camera.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a meeting the room was invited into, other participants (OST and Teams) see the room's camera as they do a Teams Room's, verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (callsC): Cause: a meeting the room is invited into is answered as a meeting join (answer_meeting_offer), but nothing told the meeting what our lines do, so the roster kept the room's main-video "recvonly" and nobody asked for it. Teams' answer to a meeting offer describes its lines (calling-shell: createAnswer adds mediaContent.mediaDescriptions when reinviteless; later changes go to links.updateMediaDescriptions as UpdateMediaDescriptions).
- Built: the answered meeting call keeps the acceptance's updateMediaDescriptions link and posts Teams' UpdateMediaDescriptions (camera sendrecv main-video / recvonly, sharing with its ss_<n> tag) once answered and whenever the camera or sharing changes (backend Describe for answered calls too, not re-offers). Also fixed re-answers to a meeting processor's mid-call re-offer: receive slots (x-ssrc-range 1-1) stay recvonly (answered sendrecv the processor ended the call: 410 subCode 301000 "x-ssrc-range must be unique/non-overlapping"). --call-test now answers even when no toast can be captured (a Teams Rooms console).
- Live (linuxlt room = OST Test Room with test camera /dev/video20; Teams on winpc as ost-test1 in Meet now "OST TEST 235 room camera", OST Test 2 on linuxlt in the same meeting): Teams invited the room via People > Request to join (no code, so the room rang; harness accepted). Room: "describing our media" -> 200; roster then showed the room's main-video sendrecv (mdRequestId 1); the processor asked for layers (encoder 428x240, then 640x360 after the mixer re-offer, re-answer 202, call kept). Teams desktop showed the room's camera tile; OST Test 2 got slot-2 for the room and decoded its frames (tile shown). Meeting ended from Teams; both OST instances' calls ended (logs). First run before the re-answer fix: Teams subscribed, then the mixer re-offer got 410 and the room dropped.
- Tests: unit test reanswers_keep_a_meetings_receive_slots_receive_only.

- 2026-11-20 merged as 8366e9f; 837 lib + 29 desktop tests pass on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Room mode: the room's camera is seen by others in a meeting it was invited into, as with a Teams Room.

- After answering an invite OST now sends Teams' UpdateMediaDescriptions (and again when camera or sharing changes), so the meeting server subscribes to the room's main video.
- Mid-call re-offers keep receive-only slots receive-only (the server had rejected sendrecv with 410 overlapping ssrc ranges); unit test added. --call-test answers on a room console.

Verified live: Teams on winpc invited OST Test Room into Meet now OST TEST 235 room camera; Teams showed the room's camera and OST Test 2 on linuxlt decoded it; meeting ended, both OST logs show the calls ended.
<!-- SECTION:FINAL_SUMMARY:END -->
