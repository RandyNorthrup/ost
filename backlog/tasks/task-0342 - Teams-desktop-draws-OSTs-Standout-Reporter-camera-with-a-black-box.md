---
id: TASK-0342
title: Teams desktop draws OST's Standout/Reporter camera with a black box
status: In Progress
assignee:
  - '@meet'
created_date: '2026-11-26T21:39:00Z'
updated_date: '2026-11-27T02:00:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0324's Teams desktop check (2026-11-26, winpc).

OST presenting in Standout or Reporter reaches Teams desktop. It labels the share "in presentation mode" and lays the camera out over or beside the content. But it draws OST's camera as an opaque rectangle: the cut-out background is black, not transparent.

Teams' own presenter camera arrives at OST with the implicit luma mask (OST clears its background), so OST's receive side matches.

Teams desktop must take the camera's alpha from something OST doesn't send. Two candidates:
- Teams' main-video stream carries roster metadata {negotiationTag: "<callId>;v_1"}; OST's has none.
- A frame or RTP signal from Teams' native engine.

Also seen in the same check: while OST controlled Teams' shared test window, "OST TEST" arrived as "OST TESt". The last Shift-held key came through lowercase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST's Standout and Reporter camera shows cut out, with no black box, in Teams desktop, verified live
- [x] #2 Keys OST sends while controlling a Teams share arrive with their modifiers, verified live
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture what Teams desktop's own Standout camera carries that OST's doesn't: RTP header extensions, SEI/SPS/PPS, SDP, roster metadata, published state, MCP requests. Done: identical apart from the camera's negotiation tag, now added.
2. Compare decoded pixel statistics of both cameras (in memory only). Done: same scheme.
3. Make the roster identical (capabilities, client version) as an experiment. Done: no change.
4. Next: receive Teams desktop's camera as X-H264UC with the native extmaps to find a native-only alpha signal.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Teams desktop was in a scheduled test meeting, sharing a window, with its status on Do not disturb while presenting.

- Keys (AC #2), 2026-11-26: OST controlled Teams desktop's shared test window on winpc and typed 16 Shift-held capitals (3.2 s with Shift down), a space and 4 more capitals. All arrived as typed. The bytes OST sends are the same for Qt keys and scan codes (generic Shift 0x10, then the letter's virtual key). The earlier "OST TESt" didn't reproduce. Teams' viewer forwards browser keydowns, auto-repeats included, so a held Shift isn't timed out on the sharer.
- Black box (AC #1): Teams desktop places OST's Standout camera by mode (lower right) but draws its background black. Compared with Teams desktop's own Standout camera (winpc C920; no frames kept), OST sends the same in every channel checked:
  - RTP: only transport-wide cc (extension 3) on Teams' camera; no SEI or PACSI units.
  - SPS: plain Constrained Baseline with VUI aspect ratio only (no video signal type or colour description).
  - SDP: no alpha attribute.
  - Published state: the same weatherPerson content.
  - MCP: the same send-layer requests to the presenter.
  - Roster: Teams' camera carries metadata.negotiationTag "<callId>;v_<n>". OST now tags its camera the same way (UpdateMediaDescriptions); Teams desktop still drew the black box.
  - Teams on the web's compositor never sets implicitMask (no cut-outs there). Teams desktop cuts out the presenter in native SlimCore (useAlpha for Standout/Reporter), so its alpha decision isn't in the JS bundles.
- Developer aid added: OST_VIDEO_META=1 logs each received video stream's extensions, NAL types and SEI/SPS/PPS/PACSI bytes (no picture data).
- Left open: AC #1. Next step: compare the decoded pixels themselves (background and edge luma/chroma of Teams' masked frames against OST's) with Teams' camera on a synthetic source, or trace SlimCore's native alpha path.

- Pixel comparison, 2026-11-26 evening. winpc Teams desktop (ost-test1) and OST on linuxlt, in the Meet-now test meeting "OST TEST 342". Statistics were computed in memory from decoded frames (OST_VIDEO_STATS=1, added here); no image or raw frame was written.
  - Teams desktop's own Standout camera: winpc C920, on about 1.5 min. Received at 320x180:
    - background (Y < 23): 79.9%, Y 0.1±0.8, U and V 128.0±0.2; (0,128,128) exactly is 77% of the frame;
    - person (Y ≥ 59): 18.9%, Y 59–198;
    - edge band (23–58): 1.2%;
    - all four corners (0,128,128); 90% of the border is background.
  - The same camera without Standout: an ordinary picture (background Y 10±5, no exact key value).
  - OST's Standout camera (synthetic test camera): background 72%, Y 0.0±0.2, U and V 128.0±0.5; (0,128,128) exactly is 68%; person Y 59–226; edge band 0.1%; corners (0,128,128). The same scheme.
  - Neither stream has an alpha or matte plane, SEI, PACSI, colour description or full-range flag. Both are 4:2:0 Constrained Baseline at the same sizes. Teams' SPS VUI adds only aspect ratio 1:1; constraint flags 0x40 vs OST's 0xC0.
- Signalling made identical (experiment only, reverted afterwards):
  - Teams desktop's roster entry has endpointCapabilities 587 (OST 579: bit 8) and clientEndpointCapabilities 15611602 (OST 9320130: supportsParticipantMapping 16, supportsImmersiveModeV2, supportsPreheatInStreamingMode).
  - Its clientVersion is "CallSignalingAgent (49/26304.…)".
  - With OST sending the same bits and the same client version, its roster entry matched Teams desktop's (587, 15611602, CallSignalingAgent), and the negotiation tags already matched. Teams desktop still drew OST's Standout camera as a black rectangle.
  - Neither field enables the cut-out, so OST keeps advertising only what it implements.
- Conclusion: the wire format, pixels, published state, roster and media descriptions are all identical, and Teams desktop still doesn't cut OST's camera out. Its cut-out is decided natively (SlimCore's compositor, useAlpha for Standout/Reporter), from something OST can't see.
  - The likeliest place is the native video path between Teams desktop endpoints and the media processor. Native Teams offers X-H264UC (MS-H264PF, PACSI/SEI) and its own header extensions (frame-counters, fast_bandwidth_feedback, video-orientation, framemarking). OST negotiates plain H.264 with transport-wide cc only, so the processor forwards Teams' camera to OST without any native-only metadata, and OST has never seen it.
  - Not reproducible from what OST receives today.
- Proposed workaround and next steps:
  1. Keep the current Standout/Reporter output. It is exactly Teams' own scheme, so OST viewers cut it out, and Teams desktop at least places the camera correctly by mode (the black rectangle is the only flaw).
  2. To find the native signal: offer X-H264UC and the native extmaps as a receiver on the camera slots, receive Teams desktop's Standout camera that way, and compare its PACSI/SEI and extensions between Standout and normal. Then send whatever differs.
  3. Optional cosmetic mitigation until then: crop OST's outgoing presenter frame to the person's box, so Teams desktop's rectangle is mostly person, not black. This changes the camera's aspect for every viewer, so only with the user's OK.
<!-- SECTION:NOTES:END -->
