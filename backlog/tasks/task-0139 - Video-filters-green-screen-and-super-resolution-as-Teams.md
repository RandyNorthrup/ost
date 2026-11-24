---
id: TASK-0139
title: Video filters, green screen and super resolution as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-14T21:42:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rest of Teams' Video effects and settings pane: Filters (Frames and Styles from Teams' catalog; Snapchat and Maybelline lenses come from third-party AR engines), Green screen settings, and Super resolution (AI upscaling of incoming video). See TASK-0064's notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Filters accordion with Teams' Frames and Styles applied to what OST sends
- [x] #2 Green screen settings as Teams
- [x] #3 Super resolution as Teams (or documented why it can't be done natively)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams' filters: video apps; the Custom Filters app's definition and page; TeamsJS video protocol.
2. Host the app as Teams does (hidden web view + TeamsJS frameless host), frames over a localhost socket, ost-vfx filter bridge.
3. Filters accordion (None, Frames/Styles chips, grid) and the pre-join Filters row.
4. Green screen settings and Super resolution (research, then build or document).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Filters (AC1): Teams' Filters are video apps; Frames/Styles = Microsoft's Custom Filters app 73d49226-b5c0-42f0-b918-acd20e8a22d8 (videoAppContentUrl https://res.cdn.office.net/midgard/1.latest/custom-filters/index.html, TeamsJS 2.23.0, WebGL/WASM). OST hosts it like Teams: VideoFilterHost.qml (hidden WebEngineView, TeamsJS frameless host via window.nativeInterface/onNativeMessage; replies must be deferred a tick or initialize times out), frames as NV12 over ws://127.0.0.1:<port>/<secret> (video_effects.rs filter_socket), ost-vfx filter bridge (newest result replaces the frame; camera never waits). A custom-scheme POST (QWebEngineUrlRequestJob::requestBody) crashed OST on Qt 6.10, hence the WebSocket.
- Verified on linuxlt (--video-filters-test, test camera A): the app initialises, readiness true for Sweet and Crystal, ~65% of sampled pixels changed by Sweet, the Crystal frame visible in the pre-join preview; pane Filters accordion and pre-join Filters row as measured.
- Snapchat/Maybelline are third-party video apps (not offered). Green screen appears in Teams' Settings tab only with a background on, the camera on and a capable device (colour picking on the preview); Super resolution is AI upscaling of incoming video.

- Green Screen (AC2): Teams keeps it in Settings ▸ Devices ▸ Video settings (the pane's link opens it there). Measured on winpc by DOM only (camera preview local): turning it on changes the preview bar to "What is your background color?" with a swatch; the swatch enters eyedropper picking. Built: Teams' Video settings card in OST's Settings ▸ Devices (preview + bar + swatch + eyedropper picking, Camera, Green Screen, Mirror my video, Adjust brightness, Soft focus), ost-vfx chroma keying of the picked colour (auto-detected backdrop before a pick; effects paused while picking), the pane's "Green screen settings" link + info. Verified on linuxlt (--green-screen-test with the sample photo): detected #46513D, picked colour keyed. Teams' Green Screen on winpc was turned back off.
- Super resolution (AC3): documented. Teams shows it only on capable devices; OST's CPU inference (tract) runs ONNX Zoo's sub-pixel CNN at ~122 ms per 224² tile, far too slow for live video, so OST behaves as an incapable device and doesn't show it (spec §3).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rest of Teams' Video effects and settings: Filters (Frames and Styles), Green Screen, and a documented decision on Super resolution.

Changes:
- Filters: Teams' Custom Filters video app hosted as Teams does (hidden web view + TeamsJS frameless host, VideoFilterHost.qml); frames as NV12 over a localhost WebSocket with a secret path; ost-vfx filter bridge; the pane's Filters accordion and the pre-join Filters row.
- Green Screen: Teams' Video settings card in Settings ▸ Devices (preview with "What is your background color?" and the eyedropper swatch, Camera, Green Screen, Mirror my video, Adjust brightness, Soft focus); ost-vfx keys out your backdrop colour (detected, or picked on the preview); the pane's "Green screen settings" link opens it.
- Super resolution: not shown — Teams hides it on devices that can't run it, and OST's CPU inference is ~0.25–0.5 s per frame (spec §3).
- Harnesses: --video-filters-test, --green-screen-test.

Tests:
- cargo test -p ost-vfx (7), cargo test -p ost-desktop video_effects
- Live on linuxlt: filters (Sweet, Crystal) in the pre-join preview; Green Screen detection and picking in Settings ▸ Devices

Not offered: Snapchat and Maybelline filters (third-party video apps).
<!-- SECTION:FINAL_SUMMARY:END -->
