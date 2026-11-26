---
id: TASK-0334
title: 'Web apps'' camera enumeration: Chromium opens raw V4L2 nodes (Avatars app)'
status: To Do
assignee: []
created_date: '2026-11-26T04:33:00Z'
labels:
  - bug
  - privacy
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0321's live checks (2026-11-26): when the Avatars app starts (pre-join with the camera off), a QtWebEngineProc process opened /dev/video0 (the laptop's real camera) for about 140 ms. That looks like Chromium's device enumeration (open + query, no capture), but QtWebEngine's Chromium lists cameras from raw V4L2 nodes, not PipeWire or the camera portal, so web apps see the same raw node list TASK-0307 removed from OST's own list and touch the real camera even when another one is chosen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is known what the Avatars app (and other hosted web apps) call on navigator.mediaDevices, and what OST's permission handling answers
- [ ] #2 Hosted web apps don't open camera devices unless a camera is granted to them, or Chromium is set to get cameras from PipeWire / the camera portal, as OST itself does
<!-- AC:END -->
