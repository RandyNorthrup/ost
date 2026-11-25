---
id: TASK-0307
title: >-
  Cameras from PipeWire: Intel IPU6 and other libcamera cameras, v4l2loopback
  (issue #1)
status: To Do
assignee: []
created_date: '2026-11-25T19:08:00Z'
labels:
  - bug
  - calls
  - github-issue
dependencies: []
references:
  - https://github.com/RandyNorthrup/ost/issues/1
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #1 (openSUSE Tumbleweed): a built-in Intel IPU6 camera that works through libcamera and PipeWire, and a v4l2loopback copy of it, don't appear in OST, while Teams in Chromium finds them. OST's camera list instead shows dozens of raw 'ipu6' device nodes that capture nothing. Chromium and Teams' web client get cameras from PipeWire (through the camera portal); OST lists raw V4L2 nodes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cameras that PipeWire offers (including libcamera cameras such as Intel IPU6) appear in OST's camera list with their proper names and work in the preview, calls and meetings
- [ ] #2 Raw V4L2 nodes that can't deliver video (IPU6 ISYS capture nodes, metadata nodes and the like) are not listed
- [ ] #3 v4l2loopback cameras are listed and work
- [ ] #4 In the Flatpak, cameras come through the camera portal
- [ ] #5 Issue #1's reporter gets a reply once the fix is released (posted only with the user's OK)
<!-- AC:END -->
