---
id: TASK-0140
title: Avatars in calls as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-18T07:35:00Z'
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

- 2026-11-17 (1295d8c): avatars as Teams runs them. OST hosts the Avatars app (96a116ab) on its app host with NAA, provides WebView2-style texture streams with camera-less NV12 frames, runs the app's own viseme model on the mic, and sends the rendered frames as a virtual camera (ost-avatar).
- UI as Teams: pre-join "Effects and avatars" tabs, the Camera flyout's Avatars tab and "Turn off Avatars", the side pane's Avatars tab hosting the app's panel, and the builder from the app bar.
- Live: OST Test 2 saw ost-test1's avatar as video.
- Open (with the agent): reaction emotes seen from the far side, solo self tile, side-pane black panel, builder header, 1280x720 at about 27 fps, last-used avatar in roaming prefs, app tile icon, and the remaining winpc measurements.
- Tests: 711 lib and 28 desktop crate tests.

Round 2 (2026-11-17):
- Self view: alone in a meeting with video (or the avatar) on, your video fills the stage at 16:9 with Teams' name tag (voice bars or muted), as measured on winpc (myself-video 1031.8 x 578.7). With video off: the 154 px picture and "Invite people to join you" (organizer or presenter) or "Waiting for others to join..." (24 px semibold). The corner self tile is back to 1:1 calls only.
- Side pane black after the guest left: QtWebEngine kept a stale frame of the pane's page (the page stayed visible, 360x166). The call window now asks the pane's pages for a new frame 0.3, 1.5 and 4 s after the roster changes. Verified in t15 (pane-left-2/4/8/16 all drawn).
- Avatar preview window: Teams' 339.3 x 198.6 box with a 330 x 185.6 video (measured on winpc).
- Quality: the avatar is sent at 1280x720, up to 30 fps (encoder 1280x720; OST Test 3 received 1280x720, Test 2 got 960x540 from the meeting's limits). Self preview at full resolution. The app renders about 28 times a second alone (Teams: 30), about 16 with a guest on the same laptop.
- Avatars app: personal-tab header with its large icon (round, on #FAFAFA), its name and Present now (Teams' dialog strings; outside a call, Meet now titled "Meeting with <you>"). The app bar shows its outline icon, tinted.
- Effect selection now sends "microsoft_none" for no background, as Teams' renderer receives it.
- Last-used avatar stays on the device: Teams' ClientPreferencesService keeps lastUsedAvatarFilter in local storage (storage.get/set, no service call), so it isn't roamed.
- Reactions: OST delivers meeting.meetingReactionReceived. The app sends Unity the same ReceivedEmoteTriggeredBroadcastChannelMessage as Teams (recorded on winpc), the emote asset loads (200), and Unity logs the same "doesn't exist in the database" warning in both. But OST's player shows no emote, while Teams shows a thumbs-up for about 4 s. Ruled out: canvas size (16x16 vs 1280x588), the main loop paused, render rate, muted visemes (0/s), background id, triggering it again. Still open.
- Tests on linuxlt: root lib 711 passed (1 ignored), ost-vfx 10 passed, desktop 28 passed (including the socket tests).

- Merged round 2 into desktop/foundation (2026-11-17): build OK, 723 lib tests passed. Open: the reaction emote isn't shown in the outgoing avatar video (the agent continues), and the app tile uses the outline icon, not the manifest colour.
<!-- SECTION:NOTES:END -->
