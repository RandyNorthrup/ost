---
id: TASK-0308
title: 'Video clips and face capture: cameras from OST''s own camera list (PipeWire)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:30:00Z'
updated_date: '2026-11-26T03:38:00Z'
labels:
  - bug
  - calls
dependencies: []
references:
  - https://github.com/RandyNorthrup/ost/issues/1
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The video clip recorder (VideoClipRecorder.qml) and Recognition's face capture (FaceCaptureDialog.qml) still use Qt Multimedia's Camera, whose Linux backend lists raw V4L2 nodes: on Intel IPU6 laptops they show dozens of 'ipu6' entries and miss the libcamera camera, as issue #1 showed for the call camera list. TASK-0307 moved calls, pre-join and Settings > Devices to PipeWire cameras (src/calling/camera.rs); these two should use the same cameras and frames.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The video clip recorder offers the same cameras as Settings > Devices (PipeWire cameras, filtered V4L2 nodes) and records from the chosen one
- [ ] #2 Face capture uses the camera chosen in Settings > Devices from the same list
- [ ] #3 No raw media-controller nodes (IPU6 ISYS and the like) appear in either
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. New desktop/src/camera_feed.rs (QML CameraFeed) + camerafeed.cpp: opens a camera from calling::camera through webrtc_video::CameraPreview::start_plain (no call effects) as a frame key; show_in(videoSink) feeds a VideoOutput, save_frame(path) writes a JPEG.
2. VideoClipRecorder.qml: drop the Qt Camera/CaptureSession/MediaRecorder (recording already goes through ClipFrames); camPreview fed from CameraFeed so the effects shaders and ClipMask keep working; Camera menu from backend.videoDevices().
3. FaceCaptureDialog.qml: VideoFrame preview from CameraFeed, picker from backend.videoDevices() (Settings' camera first), photo via save_frame instead of ImageCapture.
4. Harness --camera-privacy-test; live checks on linuxlt with virtual cameras.
<!-- SECTION:PLAN:END -->
