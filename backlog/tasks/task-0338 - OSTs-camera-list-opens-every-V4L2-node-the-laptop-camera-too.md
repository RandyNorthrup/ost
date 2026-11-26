---
id: TASK-0338
title: OST's camera list opens every V4L2 node, the laptop camera too
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T15:25:00Z'
updated_date: '2026-11-26T16:58:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: camera::v4l2_cameras() opened every /dev/video* (VIDIOC_QUERYCAP + ENUM_FMT) on each list (Settings, pre-join, call menu, test-call report, content camera, first-camera default).
2. List V4L2 nodes from sysfs + udev (name, index, dev_t, driver, v4l2loopback state/format attributes, ID_V4L_CAPABILITIES) and from what PipeWire's V4L2 monitor read (api.v4l2.cap.* on its Video/Device and Video/Source objects), without opening anything.
3. Only nodes none of those describe (other drivers, no PipeWire) are opened, only when the list is shown (video_devices) or for the chosen camera, and the result is cached by node fingerprint.
4. Unit tests: sysfs reader on a fake tree, listing rules (UVC, metadata, loopback states, IPU6, M2M), PipeWire V4L2 node table, v4l2 list that asks only undescribed nodes.
5. Live on linuxlt: bpftrace openat /dev/video* + fuser every 0.1 s, real camera chmod 000, /dev/video20 chosen: before/after at start, Settings > Devices, pre-join and a solo meeting.
<!-- SECTION:PLAN:END -->
