---
id: TASK-0140
title: Avatars in calls as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-18T02:18:00Z'
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

AC2 (2026-11-17), built the way Teams runs avatars:
- AvatarHost.qml runs Microsoft's Avatars app (96a116ab) out of sight on OST's TeamsJS host (frameContext sidePanel, NAA) while avatars are shown or are the camera. video_app_frame.js gives its frame WebView2's chrome.webview texture streams; app_host.js starts the stream (video.startVideoExtensibilityVideoStream, metadataInTexture) and builds camera-less NV12 frames in TeamsJS' one-texture layout carrying the visemes; desktop/src/avatars.rs is the localhost frame socket; vfx/src/avatar.rs asks for a frame each camera tick, keeps the app's newest and runs the app's own viseme model (VisemeModel-0.3.39.onnx: 1992 samples at 16 kHz in, 22 softmax out; tract) on the call's microphone.
- The avatar is a camera device (ost-avatar); video effects skip it. UI: pre-join Effects and avatars with Video effects | Avatars (notice, picker, create your avatar), pre-join Avatars pane, Camera flyout Avatars tab and Turn off Avatars box, side pane Avatars tab with the app's uiOnly panel and Preview / Apply avatars, the Avatars app (Avatar builder) in the app bar, own reactions sent as meeting.meetingReactionReceived, mute as audioInferenceDiscardStatusChange.
- Live on linuxlt as ost-test1: signed in, listed Avatar 1 and 70 backgrounds, applied, drew 640x360 frames in the preview and a Meet now; lip-sync output reached the app; OST Test 2 saw the avatar as ost-test1's video; builder opened; both call legs hung up (202). Teams measured on winpc (pre-join picker, FRE, flyout, side pane); the Avatars app was added for ost-test1 and Avatar 1 made there.
<!-- SECTION:NOTES:END -->
