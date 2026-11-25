---
id: TASK-0305
title: Camera stays busy after turning it on in the pre-join screen
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T18:10:00Z'
updated_date: '2026-11-25T20:57:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots: turning the camera on in the meeting pre-join screen keeps the camera device open, so the camera then fails in the call ("Device or resource busy") and the "Your camera failed" bar stays until OST is restarted. Teams hands the camera from the pre-join preview to the call without an error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Turning the camera on in pre-join and joining shows your video in the call with no error, on linuxlt with a real or virtual camera
- [x] #2 Turning the camera off and on in pre-join, in the call and after leaving never leaves the device open or the error bar stuck
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Cause: CameraPreview/VideoSender/CameraCapture drops only set a stop flag; the capture thread closed the V4L2 device later (after the next frame arrived), so the call (or a quick re-toggle) opened the camera while the preview still streamed: EBUSY.
2. Make camera release synchronous: CameraCapture always has a stop flag, the capture loop reads with a timeout and checks it, and Drop waits (bounded) for the capture thread; CameraPreview and the camera VideoSender wait for their threads, so the device is closed when drop returns.
3. Clear "Your camera failed" once the call camera turns on successfully and when the call ends.
4. PreJoin shown again for the lobby with the camera on restarts its preview.
5. Add --prejoin-camera-test harness (pre-join camera on/off/on, join, in-call toggles, bar clearing, leave, rejoin).
6. Unit tests; build/test/clippy/fmt on linuxlt; live check with a new v4l2loopback device and fd sampling.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause confirmed in code: CameraPreview/VideoSender/CameraCapture drops only set flags; the V4L2 fd closed later (preview thread up to 250 ms, capture thread only after its next frame found the receiver gone). The preheated call connects ~1.5-2 s after Join now and a re-toggle is immediate, so the next open raced the old stream. v4l2loopback answers a second streaming opener with EBUSY on S_FMT/REQBUFS (checked with two v4l2-ctl readers), as a UVC camera does.
- Fix: synchronous, bounded release (capture loop reads with a 200 ms timeout and checks a stop flag; drops wait up to 2 s for their threads). "Your camera failed" cleared when the call camera turns on and when the call ends. Lobby re-show restarts the preview.
- Harness --prejoin-camera-test; live run on linuxlt (ost-test1, /dev/video30 testsrc2 feed) passed both rounds; fd samples show 0/1 handles only, 0 after Join now before the call opens it, and 0 after leaving.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Turning the camera on in pre-join no longer leaves it busy for the call: the preview now closes the camera before Join now goes on, and "Your camera failed" goes away once the camera works again.

Cause: dropping CameraPreview, VideoSender or CameraCapture only set a flag. The preview thread noticed within 250 ms, and the capture thread closed the V4L2 device only after its next frame found the receiver gone. A preheated meeting connects about 1.5-2 s after Join now (and a quick off/on in pre-join or in the call reopens at once), so the next open hit the old stream: EBUSY on S_FMT/REQBUFS. The status bar text was never cleared.

Changes:
- src/calling/camera.rs: CameraCapture always has a stop flag; the capture loop reads with a 200 ms timeout (after a timed-out read it waits on dequeue without re-queueing) and checks the flag; Drop waits (up to 2 s, bounded by finish_thread) for the capture thread, so the device is closed when it returns.
- src/calling/webrtc_video.rs: CameraPreview and the camera VideoSender keep their thread handles and wait for them on drop (the preview loop also ends on a disconnected channel). The self frame is cleared before the next user starts, too.
- desktop/src/backend.rs: show_call_camera/clear_camera_failed clear "Your camera failed" when the call camera turns on (toggle, re-offer, join) and when the call ends; set_camera_preview logs "camera preview stopped".
- desktop/qml/PreJoin.qml: shown again for the lobby with the camera on, the preview restarts.
- desktop/qml/Main.qml: --prejoin-camera-test harness (PJCAM lines).

Tests:
- linuxlt: cargo fmt --all --check ok; cargo clippy --locked --workspace --all-targets -j 4 -- -D warnings ok; cargo test --features audio,video --lib 980 passed (3 new camera tests); cargo test -p ost-desktop 38 passed.
- Live, linuxlt, ost-test1 solo test meeting, virtual camera /dev/video30 (testsrc2): pre-join camera on, off and straight on, Join now (preheated), camera on in the call with no error; off, on, bar shown then cleared on turning on; leave; same again after rejoining. Sampled handles on the device were only ever 0 or 1, 0 after Join now before the call opened it, 0 after leaving.
<!-- SECTION:FINAL_SUMMARY:END -->
