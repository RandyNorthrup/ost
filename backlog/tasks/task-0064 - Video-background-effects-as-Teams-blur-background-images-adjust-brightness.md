---
id: TASK-0064
title: Video background effects as Teams (blur, background images, adjust brightness)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T22:33:00Z'
updated_date: '2026-11-14T19:16:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Camera ▾ flyout (Effects and settings tab) shows your preview, the cameras, a Backgrounds quick picker (None, Standard blur with its Standard/Portrait blur menu, the first catalog backgrounds), Adjust brightness and Soft focus switches and "More video effects and settings". More ▸ Video effects and settings opens the side pane with Video effects (Backgrounds, Filters) and Settings (Camera, Appearance, Advanced settings) tabs. OST's camera sent the raw picture; these need person segmentation, compositing and low-light correction on the camera path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Backgrounds as Teams in Camera ▾, the pre-join quick picker and the side pane: None, Standard blur and Portrait blur (the blur chevron menu), and Teams' catalog (still and animated backgrounds, Show all), applied to what OST sends and to your preview
- [x] #2 Adjust brightness and Soft focus as Teams (Camera ▾ and Settings tab), applied to OST's video
- [x] #3 Mirror my video switches the mirroring of your own preview (pre-join, Camera ▾, call self view) as Teams; choices persist across restarts
- [x] #4 More ▸ Video effects and settings opens Teams' side pane: Video effects tab with the Backgrounds accordion, and Settings tab (Camera, Appearance, Advanced settings with Mirror my video) as measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research (winpc, solo Meet now, camera off, 2026-11-14):
- Camera ▾ (video-button-configure-popover 359.3 wide, content 326 at 16): preview 326x180; tabs "Effects and settings" | "Avatars" (32 px); "Camera" 12 px + camera radios (34.3 rows); divider; "Backgrounds" 12 px; a row of 4 tiles 77x48 (None, Standard blur + 16 px bokeh-blur-chevron, then the first two catalog entries), 6 px apart; divider; Adjust brightness / Soft focus rows with 56x36 switches (14 px #424242 labels, rows 36 apart); divider; "More video effects and settings" (14 px, 32 high).
- Side pane "Video effects and settings" (H3 16/700, close 32x30): tabs Video effects | Avatars | Settings (44 high, 14 px/600 when selected). Video effects: accordion "Backgrounds" (341.3x32, 12 px) → grid of 88x50 tiles (radius 2, #E6E6E6) 3 per row at 109.1 px pitch, 58 rows: None, Standard blur, Add new, the catalog (16 shown), "Show all" as the last tile; "Green screen settings" link (14/500 brand) + info; accordion "Filters" (None, then Frames/Styles/Snapchat/Maybelline chips and the filter grid).
- Settings tab: Camera accordion (camera radios); Appearance: Adjust brightness (info: "Enhance the quality of your video in low light conditions."), Soft focus (info: "Smoothen your appearance for a polished look."); Advanced settings: Super resolution (info: "Enable AI-based upscaling when the incoming video resolution is low. This setting only works when your device has resources available"), Mirror my video (info: "Changing this setting will only change the view for you. This setting doesn’t currently work in Together mode."). Info popovers 241.3 wide, 12 px, padding 12.
- Blur chevron menu: 128.7x66, items 32 high (menuitemradio, 16 px checkmark, 14 px): Standard blur, Portrait blur.
- Catalog: statics.teams.cdn.office.net/evergreen-assets/backgroundimages/animated.json (6 animated MP4s, then the 70 images; name/id/filetype/src/thumb_src).
- Custom backgrounds (Add new) are synced: AMS (itemType IMAGE, views/imgpsh_fullsize_anim) or OneDrive folder "Microsoft Teams User Custom Video Backgrounds"; the list is user preference "userCustomVideoBackground" [{imageName, quickXorHash, id}], max 5, 360–2048 px, jpeg/jpg/png/bmp, aspect < 4. Moved to its own task (protocol work).
- Engine: ost-vfx crate (PP-HumanSeg 2023mar ONNX via tract; 46 ms/mask release on this PC, compositing ~10 ms at 640x360), on a worker thread; camera preview and the call's video sender both go through it.

Implementation (2026-11-14):
- Engine ost-vfx (vfx/): segmentation on a worker thread, the newest mask eased over frames; blur (Standard: /8 downscale + box blur, Portrait: /4), still and animated pictures fitted to cover, Adjust brightness (gamma lift when the mean Y < 110), Soft focus (edge-preserving 5x5 smoothing on the person). Release: 46 ms/mask, ~10 ms compositing at 640x360; built at opt-level 3 in debug too.
- webrtc_video.rs: CameraPreview and the camera's send_loop run every frame through a Processor (not screen shares); the published "self" preview is the processed frame, so it is what gets encoded.
- Desktop: video_effects.rs (catalog, downloads, apply on start and on each setting), vfxplayer.cpp (FFmpeg/swscale cover-crop to 640x360, loops; rests while no camera uses it), QML EffectTile / VideoEffectsState / VideoEffectsPane, VideoFlyout rewritten, PreJoin "Video effects" picker + pane, CallWindow side "video" (More ▸ Video effects and settings, Camera ▾ ▸ More video effects and settings), Mirror my video on all self previews.
- Verified on linuxlt with --video-effects-test --video-effects-call (camera A fed the OpenCV sample photo): None, Standard and Portrait blur, Gold shimmer holiday, Animated feeling dreamy 2, Soft focus in the pre-join preview; Camera ▾ in a Meet now shows the blurred call video; pane tabs and Settings as measured. Tile checkmark colour sampled from Teams (#8A8A8A under white).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' video effects for OST's camera: backgrounds (None, Standard blur, Portrait blur, Teams' catalog of still and animated backgrounds), Adjust brightness, Soft focus and Mirror my video, in Camera ▾, the pre-join picker and the Video effects and settings pane, applied to what OST sends.

Changes:
- New crate `vfx/` (ost-vfx): PP-HumanSeg person segmentation (ONNX via tract) on a worker thread; blur, picture/animated backgrounds, brightness and soft focus on I420 frames; unit tests and an example (`seg_bench`) that writes mask/blur/picture images.
- `src/calling/webrtc_video.rs`: camera preview and camera sender run frames through the effects (screen shares don't).
- Desktop: `video_effects.rs` (Teams' catalog from statics.teams.cdn.office.net, downloads cached, settings applied at start and on change), `vfxplayer.cpp` (FFmpeg + swscale player at the camera's size), `EffectTile`, `VideoEffectsState`, `VideoEffectsPane` (Video effects / Settings tabs, Preview / Apply and turn on video footer when the camera is off), rewritten `VideoFlyout`, pre-join "Video effects" picker and pane, mirror setting on every self preview; harness `--video-effects-test [--video-effects-call] [--video-effects-hold]`.
- Docs: spec §3 "Video effects" with the winpc measurements; desktop.md adds libswscale.

Not included (follow-ups): Add new / custom backgrounds synced through AMS/OneDrive (TASK-0138), Filters, Green screen and Super resolution (TASK-0139), Avatars (TASK-0140).

Tests:
- cargo test -p ost-vfx (5), cargo test -p ost-desktop video_effects (2), cargo test -p teams-cli --features audio,video,screencast (527 passed)
- Live on linuxlt: --video-effects-test --video-effects-call with a sample-photo test camera
<!-- SECTION:FINAL_SUMMARY:END -->
