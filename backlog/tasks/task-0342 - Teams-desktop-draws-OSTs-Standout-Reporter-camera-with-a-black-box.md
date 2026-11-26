---
id: TASK-0342
title: Teams desktop draws OST's Standout/Reporter camera with a black box
status: To Do
assignee: []
created_date: '2026-11-26T21:39:00Z'
updated_date: '2026-11-26T21:39:00Z'
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
- [ ] #2 Keys OST sends while controlling a Teams share arrive with their modifiers, verified live
- [ ] #3 OST's Take control request to a Teams desktop sharer brings up Teams' request alert (twice on 2026-11-26 Teams answered Available with AvailableAck but showed no alert for the ControlRequest, which timed out; it worked on 2026-11-16), verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Teams desktop was in a scheduled test meeting, sharing a window, with its status on Do not disturb while presenting.
<!-- SECTION:NOTES:END -->
