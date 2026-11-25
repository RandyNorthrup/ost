---
id: TASK-0322
title: Video clip recorder ignores the selected camera
status: To Do
assignee: []
created_date: '2026-11-25T22:56:00Z'
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
- [ ] #1 The clip recorder uses the camera selected in Settings ▸ Devices (and OST_CAMERA_DEVICE when set), like calls and the pre-join preview
- [ ] #2 It never opens a camera other than the selected one, checked live with two cameras
<!-- AC:END -->
