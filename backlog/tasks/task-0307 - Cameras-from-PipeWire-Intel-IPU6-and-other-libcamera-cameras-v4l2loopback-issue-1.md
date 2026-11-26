---
id: TASK-0307
title: >-
  Cameras from PipeWire: Intel IPU6 and other libcamera cameras, v4l2loopback
  (issue #1)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:08:00Z'
updated_date: '2026-11-26T03:05:00Z'
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
- [x] #1 Cameras that PipeWire offers (including libcamera cameras such as Intel IPU6) appear in OST's camera list with their proper names and work in the preview, calls and meetings
- [x] #2 Raw V4L2 nodes that can't deliver video (IPU6 ISYS capture nodes, metadata nodes and the like) are not listed
- [x] #3 v4l2loopback cameras are listed and work
- [x] #4 In the Flatpak, cameras come through the camera portal
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: camera::list_devices() kept every /dev/video* node whose (truncated) caps said capture. IPU6 ISYS nodes (driver isys, card ipu6, device caps STREAMING|IO_MC|VIDEO_CAPTURE|META_CAPTURE, formats incl. YUYV) all passed; libcamera cameras exist only in PipeWire. Capture handled YUYV only.
- PipeWire monitor (camera_pw.rs), Camera portal in the Flatpak / OST_CAMERA_PORTAL=1, V4L2 classification by raw caps (camera_node.rs), pixel formats + MJPG (pixfmt.rs, zune-jpeg), merged list without duplicates (camera.rs).
- Found live: node info updates for a state change carry no props (camera vanished while streaming); ashpd's shared zbus connection needs a long-lived runtime (second portal call hung). Both fixed.
- Codex review: never fall back to direct V4L2 when the portal is in use (fixed). Flatpak narrowed to --device=dri + camera portal; headset HID buttons documented as .deb/.rpm/AppImage only (manifest, PRIVACY.md).
- Live on linuxlt: Settings > Devices list (UVC + 3 loopbacks via PipeWire V4L2 nodes, PipeWire-only videotestsrc and GStreamer NV12 720p cameras, own v4l2loopback /dev/video40 via V4L2), each once; preview from the NV12 camera; same through the host Camera portal (loopback not in PipeWire correctly absent). --prejoin-camera-test (pre-join, meeting, toggles, rejoin) passed with the PipeWire NV12 camera and with /dev/video40. 1:1 calls ost-test1 -> OST Test 2: PipeWire camera and loopback each received by the other side.
- AC5 (reply to the reporter) waits for the release and the user's OK; draft reply in the agent report.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now gets cameras from PipeWire, as Chromium and Teams on the web do. Libcamera cameras such as Intel IPU6 can now be listed, and the raw media-controller nodes that filled the list in issue #1 no longer appear. (PR #8, addresses #1.)

Changes:
- src/calling/camera_pw.rs: a monitor thread keeps the list of PipeWire camera nodes (Video/Source with role Camera, or device.api v4l2/libcamera), with names and devids. V4L2-backed nodes are judged by their api.v4l2.cap props, and a UVC camera offered through both V4L2 and libcamera is listed once. Real cameras come before virtual ones. Capture uses target.object + node.dont-fallback and negotiates raw formats, then MJPG. In the Flatpak (or with OST_CAMERA_PORTAL=1) the connection comes from org.freedesktop.portal.Camera.
- src/calling/camera_node.rs: V4L2 nodes are classified from their raw VIDIOC_QUERYCAP caps. IO_MC, M2M, metadata, output-only and no-usable-format nodes are dropped; v4l2loopback is listed while it captures.
- src/calling/pixfmt.rs: YUYV/YVYU/UYVY, NV12/NV21, I420/YV12, RGB24/32 and MJPG (zune-jpeg) to studio-range I420, honouring strides.
- src/calling/camera.rs: merged list (PipeWire first, then V4L2 nodes PipeWire does not use, matched by path and dev_t). IDs are pipewire:<node.name> or /dev/videoN, and a saved V4L2 path resolves to the PipeWire camera. V4L2 capture picks the best format, and frames bigger than asked are scaled down. Through the portal, nothing goes around it. TASK-0305's stop-and-join is kept.
- Desktop: camera_device/video_devices/test_camera/content-camera use the new IDs. Camera controls use the V4L2 node behind a PipeWire camera. The monitor starts with the app, and Settings > Devices refills an empty camera list.
- Flatpak: --device=dri only, with cameras through the portal. Headset HID buttons are documented as .deb/.rpm/AppImage only. cargo-sources.json updated.
- Follow-up TASK-0308: the clip recorder and face capture still use Qt Multimedia's V4L2 camera list.

Tests:
- Unit tests: IPU6 ISYS/IPU3/vimc/UVC/metadata/loopback/M2M caps; PipeWire node classification, dedup and ordering; merge and resolve; every pixel format; MJPG; format pods. Root lib tests passed on linuxlt; CI on PR #8.
- Live on linuxlt:
  - Settings > Devices camera list and preview, directly and through the host Camera portal.
  - --prejoin-camera-test (pre-join, meeting, toggles, rejoin) with a PipeWire NV12 camera and with a v4l2loopback device.
  - 1:1 video calls between ost-test1 and OST Test 2 with each camera kind.

Not verified: a real IPU6/libcamera camera, which linuxlt does not have. The libcamera path is covered only by unit tests that use the properties libcamera and WirePlumber publish. The Flatpak build itself was not run; its portal code path was exercised on the host.
<!-- SECTION:FINAL_SUMMARY:END -->
