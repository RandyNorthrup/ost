---
id: TASK-0334
title: 'Web apps'' camera enumeration: Chromium opens raw V4L2 nodes (Avatars app)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T04:33:00Z'
updated_date: '2026-11-26T15:54:00Z'
labels:
  - bug
  - privacy
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0321's live checks (2026-11-26): when the Avatars app starts (pre-join with the camera off), a QtWebEngineProc process opened /dev/video0 (the laptop's real camera) for about 140 ms. That looks like Chromium's device enumeration (open + query, no capture), but QtWebEngine's Chromium lists cameras from raw V4L2 nodes, not PipeWire or the camera portal, so web apps see the same raw node list TASK-0307 removed from OST's own list and touch the real camera even when another one is chosen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 It is known what the Avatars app (and other hosted web apps) call on navigator.mediaDevices, and what OST's permission handling answers
- [x] #2 Hosted web apps don't open camera devices unless a camera is granted to them, or Chromium is set to get cameras from PipeWire / the camera portal, as OST itself does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Trace /dev/video* opens (bpftrace, fuser) and Chromium media logs while the Avatars app starts
2. Find which page call makes Chromium list cameras
3. Gate embedded pages: enumerateDevices / devicechange / getUserMedia(video) until the page holds a device or the app has Media permission
4. Verify no opens, Avatars still works, and a granted app still gets its camera
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC1, what the Avatars app does (AvatarRenderer.framework.js, Unity; traced with a diagnostic copy of the gate and Chromium's media_stream_manager log): enumerateMediaDeviceList calls navigator.mediaDevices.enumerateDevices(); updateVideoInputDevices adds a "devicechange" listener on navigator.mediaDevices; it also makes an AudioContext and MediaStreamTrackGenerators (Teams' texture streams). No getUserMedia. The devicechange listener made Chromium start monitoring and list every device (VIDEO_INPUT through the video capture service, which opens every /dev/video*), each time the app started. OST's permission handler was never asked: no permission request is made for a listing.
- Probes in Whiteboard's frames: devicechange listener -> full listing; enumerateDevices -> full listing; AudioContext and setSinkId -> audio outputs only; permissions.query and MediaStreamTrackGenerator -> nothing.
- PipeWire / camera portal route not available: Ubuntu's Qt WebEngine 6.10.2 has no PipeWire camera support compiled in (no WebRtcPipeWireCamera or pipewire strings in libQt6WebEngineCore).
- Fix: src/media_gate.js in every frame of OST's web profile (a profile user script) and the Custom Filters view: until the page holds the camera or microphone (a stream given, or a permission granted) enumerateDevices() answers Chromium's no-permission placeholder without asking Chromium and devicechange listeners are held, then handed over; getUserMedia with video is refused unless the app's Media permission is on (WebApp marks its frames, read again on each load); frames a page makes are gated when it reaches them.
- Live (linuxlt; /dev/video0 and video1 chmod 000 during the tests so the real camera could not be opened; bpftrace on openat of /dev/video* plus fuser every 0.1 s): before (runs tour6, tour10) every Avatars start -> QtWebEngineProc opened video0, video1, video20-22 (~140 ms); with the gate, 3 Avatars starts in a call -> no QtWebEngineProc open, no Chromium VIDEO_INPUT listing, no QtWebEngineProc in the fuser log; Avatars still listed (1 avatar, 70 backgrounds), registered for frames and rendered. Whiteboard without Media permission: getUserMedia(video) -> NotAllowedError, no listing; with Media permission on: OST's handler granted it and the page got "OST test camera A".
- Found: ost-desktop itself opens every /dev/video* node (the real camera too) at start and when a call starts -> TASK-0338.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Embedded pages no longer make Chromium open camera devices before they hold a camera or microphone.

Why: Qt WebEngine's Chromium lists cameras by opening every /dev/video* node (V4L2; the distributions' Qt WebEngine has no PipeWire camera) whenever a frame calls enumerateDevices(), adds a devicechange listener or asks for a camera, before any permission is decided. Teams' Avatars renderer does the first two as it starts, so each start opened the laptop camera (~140 ms).

Changes:
- desktop/src/media_gate.js (new): in every frame of OST's web profile (profile user script, Main.qml) and the Custom Filters view (VideoFilterHost.qml). Until the page holds the camera or microphone: enumerateDevices() answers Chromium's no-permission placeholder without asking Chromium; devicechange listeners are held and handed over later; getUserMedia with video is refused unless the app's Media permission is on (WebApp.qml marks its frames, read again on each load). Child frames are gated when reached. --media-gate-log logs it (docs/desktop.md).
- backend.mediaGateScript(); docs/spec/app-host.md "Media devices in embedded pages".

Tests (live, linuxlt; real camera chmod 000; bpftrace on openat /dev/video* + fuser every 0.1 s):
- Before: every Avatars start -> QtWebEngineProc opened video0, video1, video20-22.
- After: Avatars started 4 times (3 in a call, 1 in --avatar-test) -> no QtWebEngineProc open, no Chromium VIDEO_INPUT listing; Avatars listed, registered and drew as before.
- Whiteboard: camera refused without Media permission (no listing); granted with it ("OST test camera A").

Follow-up: TASK-0338 (OST's own camera list opens every V4L2 node).
<!-- SECTION:FINAL_SUMMARY:END -->
