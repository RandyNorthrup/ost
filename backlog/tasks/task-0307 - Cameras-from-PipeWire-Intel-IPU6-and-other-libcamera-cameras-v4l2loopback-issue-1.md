---
id: TASK-0307
title: >-
  Cameras from PipeWire: Intel IPU6 and other libcamera cameras, v4l2loopback
  (issue #1)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:08:00Z'
updated_date: '2026-11-25T19:17:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: camera::list_devices() opens every /dev/video* and keeps any node whose (truncated) caps say VIDEO_CAPTURE; IPU6 ISYS nodes (driver isys, card ipu6, device caps STREAMING|IO_MC|VIDEO_CAPTURE|META_CAPTURE) pass, libcamera cameras (PipeWire only) are never seen; capture only handles YUYV (anything else passed through as I420).
2. PipeWire camera monitor (new src/calling/camera_pw.rs): a long-lived PipeWire connection keeps the Video/Source camera nodes (media.role Camera or device.api v4l2/libcamera) with names, devids and backing V4L2 path; in the Flatpak it connects through the xdg-desktop-portal Camera portal (AccessCamera + OpenPipeWireRemote). Capture streams from a node by serial, negotiating raw formats (I420, YV12, NV12, NV21, YUY2, YVYU, UYVY, RGB/BGR 24/32-bit) and MJPG.
3. V4L2 node classification (new src/calling/camera_node.rs): raw device caps (incl. IO_MC), skip media-controller nodes, metadata/output-only/M2M nodes, require a usable pixel format; v4l2loopback listed (capture caps, exclusive_caps aware). Unit tests with IPU6 ISYS, UVC metadata, loopback, M2M capability data.
4. Merged list in camera.rs: PipeWire cameras first, then V4L2 nodes not already exposed by PipeWire (dedup by api.v4l2.path and device.devids dev_t); IDs pipewire:<node.name> or /dev/videoN; saved /dev paths resolve to the PipeWire node wrapping them. V4L2 capture picks the best supported format and honours bytesperline.
5. Pixel conversion module (src/calling/pixfmt.rs) to I420 incl. MJPG (zune-jpeg) with tests; frames larger than asked are scaled down.
6. Desktop: camera_device()/video_devices()/test_camera accept and resolve the new IDs; camera controls map PipeWire V4L2 nodes to their /dev path; room device camera lookup; Flatpak manifest comment + cargo-sources.json.
7. Tests on linuxlt (root lib tests, desktop tests, clippy, fmt); live: own v4l2loopback device + GStreamer/pw PipeWire-only camera node in Settings > Devices, pre-join and a test call between test accounts; portal path checked with host xdg-desktop-portal.
8. Follow-up task for Qt Multimedia camera users (video clips recorder, face capture) which still list V4L2 via Qt.
<!-- SECTION:PLAN:END -->
