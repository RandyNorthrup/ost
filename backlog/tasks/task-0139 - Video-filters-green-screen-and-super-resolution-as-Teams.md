---
id: TASK-0139
title: Video filters, green screen and super resolution as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-14T21:02:00Z'
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
- [ ] #2 Green screen settings as Teams
- [ ] #3 Super resolution as Teams (or documented why it can't be done natively)
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
<!-- SECTION:NOTES:END -->
