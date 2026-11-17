---
id: TASK-0140
title: Avatars in calls as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-17T08:21:00Z'
labels:
  - calls
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Camera ▾ flyout, pre-join quick picker and Video effects and settings pane have an Avatars tab: join as your Microsoft avatar instead of video. Needs research into Teams' avatar service and rendering (see TASK-0064's notes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Research documents how Teams' avatars are stored, rendered and sent
- [ ] #2 Avatars work in OST the way Teams runs them: the Avatars video app (96a116ab…) hosted as a video app with camera-less frames, the viseme lip-sync model on the mic, avatars listed as effects, reactions and the Avatar builder tab, matched to Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: research (421a09d, docs/spec/call-and-meeting-window.md, Avatars): Teams offers avatars only in the desktop app on WebView2 (texture streams, cores/memory, SlimCore minimum, not VDI); the Avatars app is a Unity WebGL2 video app that runs only inside a frame, signs in by NAA, stores avatars with Mesh, and asks the host for NV12 frames plus a viseme model run on the mic; others just see camera video. Microsoft's avatar assets have no public format, so the faithful route is Teams' own: host that app as a video app on OST's app host and video-filter bridge. Until then OST shows what Teams shows on a device without avatar support.
<!-- SECTION:NOTES:END -->
