---
id: TASK-0322
title: Video clip recorder ignores the selected camera
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T08:16:00Z'
labels:
  - bug
  - privacy
  - chat
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The video clip recorder (desktop/qml/VideoClipRecorder.qml) ignores the selected camera and OST_CAMERA_DEVICE and opens the default camera.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The clip recorder uses the camera selected in Settings ▸ Devices (and OST_CAMERA_DEVICE when set), like calls and the pre-join preview
- [x] #2 It never opens a camera other than the selected one, checked live with two cameras
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: the recorder's Qt Camera picks from QMediaDevices.videoInputs and falls back to Qt's defaultVideoInput: the setting cameraDevice (pipewire:/dev path) and OST_CAMERA_DEVICE never reach it.
2. With TASK-0308's CameraFeed, "" opens backend::selected_camera() (OST_CAMERA_DEVICE, else Settings > Devices), resolved in OST's camera list; the Camera menu lists Settings > Devices' cameras.
3. Live: two v4l2loopback cameras, the chosen one only is opened (OST_CAMERA_DEVICE run and Settings run).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: the recorder picked from QMediaDevices.videoInputs or Qt's defaultVideoInput; the cameraDevice setting and OST_CAMERA_DEVICE never reached it.
- Fix: CameraFeed with "" opens backend::selected_camera() (OST_CAMERA_DEVICE, else Settings > Devices; never the avatar); the recorder resets to it each time it opens; its Camera menu lists Settings' cameras.
- Live (linuxlt, UVC + loopback A/B + PipeWire test camera): env A -> only A opened; Settings B -> only B, picture shown; Settings B + recorder pick A while recording -> only A, clip shows A; PipeWire camera via env -> only its stream. Real camera never opened.

- Follow-up in PR #12: a chosen camera that is missing is waited for (retried each second), never replaced by another camera.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The video clip recorder now uses the camera chosen in Settings > Devices (or OST_CAMERA_DEVICE), and the Camera menu lists the same cameras (PR #12).

Cause: it used Qt Multimedia's camera list and default camera, which knew nothing of OST's setting.

Tests: live on linuxlt with two v4l2loopback cameras and a PipeWire camera; only the chosen camera was ever opened, and the recorded clip shows it.
<!-- SECTION:FINAL_SUMMARY:END -->
