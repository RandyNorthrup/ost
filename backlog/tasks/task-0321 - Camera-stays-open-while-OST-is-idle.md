---
id: TASK-0321
title: Camera stays open while OST is idle
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T03:38:00Z'
labels:
  - bug
  - privacy
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). Every running OST instance keeps the camera device (/dev/video0) open even when no call, preview or clip recorder is using it, so the camera can't be used elsewhere and may show as in use. Teams opens the camera only while it shows video.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST opens a camera only while a preview, call video, video effects preview or clip recording is active, and closes it within a second of the last one stopping
- [ ] #2 With OST idle (no call, no preview), no camera device is open (checked with fuser/lsof on linuxlt)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: Conversation.qml and NewChat.qml create VideoClipRecorder eagerly, SettingsView creates FaceCaptureDialog eagerly; each has a Qt Multimedia Camera whose cameraDevice is set (the default camera when none is picked). Qt's V4L2 camera opens the device to read its controls as soon as cameraDevice is set and keeps that fd until the camera object goes, active or not.
2. Remove Qt Multimedia cameras from both (TASK-0308): a CameraFeed QML type over OST's capture (calling::camera), open only while the recorder/face dialog shows the camera, closed (joined) when it stops.
3. Live on linuxlt with v4l2loopback cameras: idle OST holds no /dev/video*; the recorder and face capture open only the chosen camera and close within 1 s; pre-join/call (--prejoin-camera-test) and the video effects preview unchanged.
<!-- SECTION:PLAN:END -->
