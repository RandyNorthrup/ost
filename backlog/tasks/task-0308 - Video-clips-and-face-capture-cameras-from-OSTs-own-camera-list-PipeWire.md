---
id: TASK-0308
title: 'Video clips and face capture: cameras from OST''s own camera list (PipeWire)'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:30:00Z'
updated_date: '2026-11-26T06:23:00Z'
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
- [x] #1 The video clip recorder offers the same cameras as Settings > Devices (PipeWire cameras, filtered V4L2 nodes) and records from the chosen one
- [x] #2 Face capture uses the camera chosen in Settings > Devices from the same list
- [x] #3 No raw media-controller nodes (IPU6 ISYS and the like) appear in either
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. New desktop/src/camera_feed.rs (QML CameraFeed) + camerafeed.cpp: opens a camera from calling::camera through webrtc_video::CameraPreview::start_plain (no call effects) as a frame key; show_in(videoSink) feeds a VideoOutput, save_frame(path) writes a JPEG.
2. VideoClipRecorder.qml: drop the Qt Camera/CaptureSession/MediaRecorder (recording already goes through ClipFrames); camPreview fed from CameraFeed so the effects shaders and ClipMask keep working; Camera menu from backend.videoDevices().
3. FaceCaptureDialog.qml: VideoFrame preview from CameraFeed, picker from backend.videoDevices() (Settings' camera first), photo via save_frame instead of ImageCapture.
4. Harness --camera-privacy-test; live checks on linuxlt with virtual cameras.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- CameraFeed QML type (desktop/src/camera_feed.rs + camerafeed.cpp) over webrtc_video::CameraPreview::start_plain (no call effects): picture as a frame key, pushed into a VideoOutput sink (showIn) or drawn by VideoFrame; saveFrame writes a JPEG.
- Recorder: camPreview fed from CameraFeed (effects shaders and ClipMask unchanged); dead Qt CaptureSession/MediaRecorder removed (recording is ClipFrames in every mode).
- Face capture: same list, Settings' camera first, VideoFrame preview, photo via saveFrame.
- Gotcha: #[auto_cxx_name] has to be on the invokables block too, or QML sees show_in/save_frame (showIn "is not a function").
- AC3 by construction (camera::cameras(), TASK-0307's filtered list); no IPU6 hardware to check live.

- Codex review (PR #12): retry while no camera (portal pending): both dialogs look again each second while shown. Live: PipeWire camera started 2 s after open -> picked up within ~1 s.
- Found in that check: face capture took videoDevices().current, which falls back to the first camera when the chosen one is missing, and opened linuxlt's real webcam ~6 s (harness photo deleted unviewed, nothing sent). Fixed: "" = the chosen camera resolved in CameraFeed, which opens a chosen camera only as itself (no listing) and the first camera only when none is chosen.

- Codex review 2: CameraFeed opens on a worker thread (`opening`; stale results dropped, which closes their camera); a camera that stops by itself (start_plain callback) closes the feed so the retry reopens it. Live: PipeWire camera removed while the recorder showed it -> noticed in 60 ms, reopened 1 s after it came back; V4L2 loopback path unchanged.

- Codex review 3: close() cancels an open under way (CameraCapture::start_cancellable -> camera_pw::capture polls the flag while waiting for the link, ends and joins the stream); the recorder clears its picture whenever the camera stops. Live: open + camera off at once -> PipeWire stream never linked, gone in ~120 ms.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The video clip recorder and face capture now use OST's own camera list and capture (PipeWire, the camera portal, filtered V4L2), the same as calls (PR #12).

Changes:
- desktop/src/camera_feed.rs, camerafeed.cpp: CameraFeed QML type (open/close, showIn(videoSink), saveFrame(path)); webrtc_video::CameraPreview::start_plain.
- VideoClipRecorder.qml: CameraFeed into camPreview; Camera menu from backend.videoDevices(); Qt camera session removed.
- FaceCaptureDialog.qml: CameraFeed + VideoFrame; photos from the newest picture.
- --camera-privacy-test harness.

Tests: live on linuxlt (loopback and PipeWire cameras): lists match Settings > Devices, the chosen camera is shown and recorded, the photo JPEG is right. Not verified: a real IPU6 camera; the Flatpak portal path for these dialogs.
<!-- SECTION:FINAL_SUMMARY:END -->
