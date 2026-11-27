---
id: TASK-0342
title: Teams desktop draws OST's Standout/Reporter camera with a black box
status: In Progress
assignee:
  - '@meet'
created_date: '2026-11-26T21:39:00Z'
updated_date: '2026-11-27T00:42:00Z'
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
1. Capture what Teams desktop's own Standout camera carries that OST's doesn't: RTP header extensions, SEI/SPS/PPS, SDP, roster metadata, published state, MCP requests.
2. Make OST send what differs; check Teams desktop's view of OST's Standout camera live.
3. Re-test the lost-Shift typing under remote control with a long held-Shift run; fix if it reproduces.
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
<!-- SECTION:NOTES:END -->
