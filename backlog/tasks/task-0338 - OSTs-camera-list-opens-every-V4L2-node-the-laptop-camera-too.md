---
id: TASK-0338
title: OST's camera list opens every V4L2 node, the laptop camera too
status: To Do
assignee: []
created_date: '2026-11-26T15:25:00Z'
labels:
  - bug
  - privacy
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0334's checks (2026-11-26, bpftrace on openat /dev/video* on linuxlt): ost-desktop itself opens every /dev/video* node (the laptop's Integrated Camera /dev/video0 and /dev/video1 as well as the v4l2loopback test cameras) once at start and again when a call or pre-join starts, presumably to read each node's capabilities for the camera list (TASK-0307's filtered V4L2 nodes). It is an open for querying, not a capture, but it touches the real camera even when another one is chosen and none is on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With OST idle and when a call or pre-join starts, no camera node is opened except through PipeWire / the camera portal, or only the chosen camera (bpftrace on openat of /dev/video* shows it)
<!-- AC:END -->
