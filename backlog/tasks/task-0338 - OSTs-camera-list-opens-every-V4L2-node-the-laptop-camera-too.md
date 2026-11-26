---
id: TASK-0338
title: OST's camera list opens every V4L2 node, the laptop camera too
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T15:25:00Z'
updated_date: '2026-11-26T18:45:00Z'
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
- [x] #1 With OST idle and when a call or pre-join starts, no camera node is opened except through PipeWire / the camera portal, or only the chosen camera (bpftrace on openat of /dev/video* shows it)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: camera::v4l2_cameras() opened every /dev/video* (VIDIOC_QUERYCAP + ENUM_FMT) on each list (Settings, pre-join, call menu, test-call report, content camera, first-camera default).
2. List V4L2 nodes from sysfs + udev (name, index, dev_t, driver, v4l2loopback state/format attributes, ID_V4L_CAPABILITIES) and from what PipeWire's V4L2 monitor read (api.v4l2.cap.* on its Video/Device and Video/Source objects), without opening anything.
3. Only nodes none of those describe (other drivers, no PipeWire) are opened, only when the list is shown (video_devices) or for the chosen camera, and the result is cached by node fingerprint.
4. Unit tests: sysfs reader on a fake tree, listing rules (UVC, metadata, loopback states, IPU6, M2M), PipeWire V4L2 node table, v4l2 list that asks only undescribed nodes.
5. Live on linuxlt: bpftrace openat /dev/video* + fuser every 0.1 s, real camera chmod 000, /dev/video20 chosen: before/after at start, Settings > Devices, pre-join and a solo meeting.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: camera::v4l2_cameras() opened every /dev/video* (QUERYCAP + ENUM_FMT) on each camera list; on linuxlt that is Settings > Devices (twice per visit), the call's camera menu, the test-call report and the content camera.
- Fix: sysfs + udev + PipeWire's V4L2 monitor props decide each node without opening it (camera_node::SysNode/Listing, camera_pw::v4l2_nodes); only nodes nothing describes are opened, when the list is shown or for the chosen camera, cached by fingerprint.
- Tracing: the sys_enter_openat str() filter missed opens on linuxlt (kernel 7.2, bpftrace 0.25; even a python3 test open), so runs also traced fentry:vmlinux:may_open (open attempts, incl. EACCES on the chmod 000 real camera) and fentry:videodev:v4l2_open (opens that reach V4L2), with a python3 check open per run.
- Live (linuxlt; /dev/video0+1 chmod 000 during runs, restored to 660 + ACL; own v4l2loopback /dev/video41 fed by GStreamer chosen; own PipeWire-only camera for a second set):
  - before, start + Settings pages: OST tried video0 x2, video1 x2 (denied), opened video20/21/22 x2 each, video41 x4; nothing at start.
  - after, same: video41 x2 only (the chosen camera's preview); list unchanged (Integrated Camera, OST camlist camera).
  - before/after, pre-join + solo meeting x2 (--prejoin-camera-test): video41 x10 each (camera on each time), nothing else; all checks passed.
  - after with the PipeWire camera chosen: Settings and pre-join + meeting x2 -> 0 V4L2 opens by OST.
- Mic incident: cpal ignores PULSE_SOURCE; the baseline meeting run recorded from linuxlt's built-in mic (alsa_input.pci-...) for about 10 s (joined muted) until I moved the stream; the first after-run's two streams were moved by a guard within 0.2 s. Later runs used OST_MIC_DEVICE=<remap-source node name> (null sink + module-remap-source) and recorded from it directly (pactl checked).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST no longer opens camera nodes to build its camera list. Before, every list (Settings > Devices, the call's camera menu, the test-call report, the content camera) opened every /dev/video* node, including the laptop's real camera.

Changes:
- src/calling/camera_node.rs: SysNode reads sysfs (name, index, dev, parent driver, v4l2loopback state/format) and udev's ID_V4L_CAPABILITIES without opening anything. Listing classifies the node: UVC picture vs metadata nodes, loopback fed or idle (and exclusive_caps=0), no capture. Other drivers are Unknown.
- src/calling/camera_pw.rs: v4l2_nodes() returns the V4L2 nodes PipeWire's monitor describes (api.v4l2.cap.* on its Video/Device and Video/Source objects), cameras or not. That covers IPU6 ISYS nodes.
- src/calling/camera.rs: the V4L2 fallback skips nodes PipeWire cameras use, then goes by sysfs/udev, then by PipeWire's caps. Only a node none of them describes is opened (Probe): while the list is shown (cameras_shown) or for the chosen camera (cameras_with). The answer is cached by the node's fingerprint. cameras() opens nothing. first_camera() probes only when nothing else is a camera.
- Desktop: video_devices uses cameras_shown; test_camera, camera_feed and same_camera ask only for the chosen camera.

Tests:
- Unit tests: sysfs reader on a fake tree; listing rules (UVC, metadata, loopback states and formats, IPU6, M2M, makedev); PipeWire V4L2 node table; a fallback that only asks undescribed nodes; Probe rules.
- Live on linuxlt (real camera chmod 000; bpftrace may_open + v4l2_open + openat, fuser every 0.1 s; chosen camera = own v4l2loopback):
  - Start + Settings: before, video0/1 tried twice and 20/21/22 opened twice; after, only the chosen camera's preview.
  - Pre-join + solo meeting x2: only the chosen camera, before and after.
  - With a PipeWire camera chosen: no V4L2 open at all.

Not verified live: an Unknown-driver node (capture card, IPU6 without PipeWire), which linuxlt doesn't have. That path is covered by unit tests.
<!-- SECTION:FINAL_SUMMARY:END -->
