---
id: TASK-0321
title: Camera stays open while OST is idle
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T08:16:00Z'
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
- [x] #1 OST opens a camera only while a preview, call video, video effects preview or clip recording is active, and closes it within a second of the last one stopping
- [x] #2 With OST idle (no call, no preview), no camera device is open (checked with fuser/lsof on linuxlt)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: Conversation.qml and NewChat.qml create VideoClipRecorder eagerly, SettingsView creates FaceCaptureDialog eagerly; each has a Qt Multimedia Camera whose cameraDevice is set (the default camera when none is picked). Qt's V4L2 camera opens the device to read its controls as soon as cameraDevice is set and keeps that fd until the camera object goes, active or not.
2. Remove Qt Multimedia cameras from both (TASK-0308): a CameraFeed QML type over OST's capture (calling::camera), open only while the recorder/face dialog shows the camera, closed (joined) when it stops.
3. Live on linuxlt with v4l2loopback cameras: idle OST holds no /dev/video*; the recorder and face capture open only the chosen camera and close within 1 s; pre-join/call (--prejoin-camera-test) and the video effects preview unchanged.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: VideoClipRecorder (created with Conversation.qml and NewChat.qml) and FaceCaptureDialog (created with SettingsView) each had a Qt Multimedia Camera with cameraDevice set (Qt's default camera when none was picked). Qt's V4L2 camera opens the device for its controls when the device is set and keeps the fd until the object goes, active or not.
- Fix together with TASK-0308: neither uses Qt's camera any more; CameraFeed opens OST's capture only while the dialog shows the camera.
- Live on linuxlt (fd + PipeWire sampler every 0.1 s): idle signed-in OST 50 s, no camera handle; recorder close -> device closed in 24 ms (V4L2) / 22 ms (PipeWire stream); face capture ~0.1 s; --prejoin-camera-test and --video-effects-test unchanged.
- One intermediate review-fix build let face capture fall back to the first camera when the chosen one was missing: it opened linuxlt's real webcam ~6 s (harness photo deleted unviewed, nothing sent); fixed before the final push, rechecked.
- Seen: QtWebEngineProc opened /dev/video0 ~140 ms when the Avatars app started (Chromium enumeration); tracked separately.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST no longer keeps a camera open while idle (PR #12).

Cause: the video clip recorder and face capture dialogs are created up front and each held a Qt Multimedia Camera with a device set; Qt's V4L2 camera keeps the device open from then on, active or not.

Changes (with TASK-0308): both dialogs now use CameraFeed (OST's own capture), opened only while they show the camera (on a worker thread, cancelled if closed meanwhile) and closed as soon as they stop.

Tests: live on linuxlt with an fd/PipeWire sampler: idle OST holds no camera; recorder/face capture open the chosen camera only and close within 0.1 s; pre-join, call and video effects preview unchanged (--prejoin-camera-test, --video-effects-test).
<!-- SECTION:FINAL_SUMMARY:END -->
