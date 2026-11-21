---
id: TASK-0137
title: >-
  Recorder effects as Teams: Backdrop, Text, Draw, Stickers, Filter, Frame,
  Board, Photo
status: To Do
assignee:
  - '@claude'
created_date: '2026-11-14T15:44:00Z'
updated_date: '2026-11-21T16:10:00Z'
labels:
  - messages
  - video
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' video clip recorder (Stream's) has Backdrop (None, Upload, Blur, Microsoft's stock images and videos, needing background segmentation) and an Effects menu (Text, Draw, Stickers, Filter, Frame, Board, Photo), plus Draw while screen recording. OST's native recorder (TASK-0136) needs them, recorded as part of the picture.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backdrop: None, Upload, Blur and the image/video library, applied to the camera picture as Teams does
- [ ] #2 Effects menu: Text, Draw, Stickers, Filter, Frame, Board and Photo, each as Teams, recorded into the clip
- [ ] #3 Draw while screen recording, as Teams
- [ ] #4 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-14 research: in screen recording the Effects menu is Text, Backdrop (disabled), Stickers, Filter, Frame, Board, Photo; in camera mode Text, Draw, Stickers, Filter, Frame, Board, Photo. Text = an input (384x66) centred on the picture, big white text with a dark outline. Esc in Teams closes the whole recorder.
- Stream's chunks hold the catalogs (scratchpad sce/: 629.js boards: 16 boards with 16x9/9x16 images and icons; 630.js filters: LUT (16-square) + sprite overlay (ADD, 0.18) + two-tone/pixelate/exposure/contrast definitions; 631.js frames/backdrops; 288.js editor tools: bringForward, sendBackward, duplicate, flip, trash, shapes, timer).
- Backdrop needs background segmentation, shared with TASK-0064 (call video effects): do 0064 first.

- 2026-11-20 (chatC): wrote an implementation spec of Stream's recorder effects from Stream's bundles (scratchpad chatC/recorder-effects-spec.md, about 96 KB, copied to the scratchpad root; with recorder-stickers.json (446 stickers) and recorder-filters.json (18 filters); chunks in chatC/sce2).
  - Everything is drawn into Stream's render canvas and recorded. Layers, bottom to top: backdrop and person, board, filter, text, drawings, stickers and photos, frame.
  - Camera mode bar: Camera, Mic, Screen | Backdrop, Script, Effects ▾ (Text, Draw, Stickers, Filter, Frame, Board, Photo). Screen mode: Script and Draw move onto the bar; Backdrop is disabled.
  - Filter per-pixel order: pixelate, LUT, animated overlay, two-tone, exposure, contrast, image overlay.
  - Backdrop edge: smoothstep(0.3, 0.8, mask); bg·(1−a) + cam·a².
  - Draw: one colour slider, thickness 1–60 (4 to start), Undo / Redo / Clear.
  - Text: 6 styles at 68 px on a 761 x 428 picture.
  - Board: a split screen, 50/50 to start.
  - Catalogs: 31 frames, 16 boards, 36 backdrops, 18 filters, 446 stickers, all on the public CDN.
  - Teams' "None / Upload / Blur" backdrop panel is the AugLoop variant; its stock list comes over AugLoop and isn't enumerated.
- Not built in this pass. It still needs measuring on winpc with the camera, during a test recording.

- 2026-11-20 (recD) measured live on winpc with Chromium's fake camera (WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS --use-fake-device-for-media-stream --use-file-for-fake-video-capture=<mjpeg>; no real webcam). Captures and reference shots: scratchpad rec137/ (cap4.txt = AugLoop session start, ref/*.png).
  - Teams runs the AugLoop variants: Backdrops (None/Upload/Blur, Search, Images/Videos tabs, sections "Images"/"Videos" with See more; home shows 24 each, See more/search 50) and Stickers (Hubble emoji: Smilies, Animals, Food, Objects, People, Hand gestures, Travel and places, Activities, Symbols; home 33 each). Filter/Frame/Board are the local catalogs of the spec.
  - AugLoop: wss://augloop.svc.cloud.microsoft/, SessionInit appName "Testing"; activate AugLoop_Hubble_ProviderContentAnnotation and ContentDownloadAnnotation (token); ContentSearchSignal per pivot: backdrops f8218404… (images) / 32318599… (videos) with orderBy modifiedDate + filter tags/any(p: p eq 'background'), pageSize 50; stickers pivot 84e04d41… with select "svg3D, skins/svg3D, thumbnailInfo/size100", filter pivotNames/any(p: p eq '<category>'), app 1010. Applied assets: image part "Image" (…_medium.jpg, stretched to 16:9), video part "Video" (.mp4 1920x1080), sticker part "SVG" (…_color.svg).
  - Drawer: white 95 %, radius 8, padding 8 16 20, centred, bottom = container bottom + 25 % of its height (small window); width 90 % (Backdrops/Stickers 720 x 390, overflowing the dialog), Filter/Frame/Board 608, Draw 480, Photo 680. Effects menu: Fluent menu 138 wide, 32-px rows, opens above the button.
  - Canvas history (Clear video canvas / Undo / Redo) sits in the header after the title (32 x 31.3 at 161.6/201.6/241.6). Selected objects show a right-hand dock (pill rgba(177,177,177,.48), radius 12, 33.3 wide at x 750.7): Delete, Flip, Duplicate, Forward, Backward; text shows Font, Color, Stroke, Background. Sticker = 100 px wide on the 761 picture, text 68 px at 1280 (~40 px shown), board camera left/board right 50 %.

- 2026-11-20 (recD) built (uncommitted, worktree agent-a7bf3496e5f9bc281): api::hubble (AugLoop stock search, anonymous; examples/hubble_search works live), backend.hubbleSearch/hubbleResults, ClipMask (clip_mask.rs + clipmask.cpp: QVideoSink frames -> ost-vfx segmentation -> mask texture), shaders desktop/shaders/clip_{filter,camera,board}.frag baked by build.rs with qsb (linuxlt: installed qt6-shader-baker), QML ClipCatalog/ClipEffectsState/ClipCanvasItems/ClipEditOverlay/ClipDrawer/ClipEffectPanels, recorder bar (Backdrop, Draw in screen mode, Effects menu), header Clear/Undo/Redo, camera mode now records through ClipFrames (effects burned in). Harness --recorder-effects-test [--recorder-cam=<name>] [--recorder-effects-screen]; linuxlt run script scratchpad rec137/run_fx.sh (feeds test camera B the person photo).

- 2026-11-21 (recD) live on linuxlt (test2, harness --recorder-effects-test --recorder-cam="OST test camera C" --recorder-chat="OST Test 1"; camera C = a v4l2loopback device added for this, fed /tmp/ost-person.jpg): menu, Backdrops (50+50 Hubble items), stock image (stretched, matches Teams pixel for pixel), Blur (strength now as Teams), stock video, Stickers (9 x 50), sticker + dock, Filter (Lift LUT maths checked against Teams' Lift: mean error 0.009 vs 0.052 unfiltered), Vintage, B&W, Bricks, Frame, Board, Draw, Text, Photo; a 4-6 s recording carries blur, cut-out, filter, stroke, sticker, text and frame at 1280x720; screen mode: menu (Backdrop disabled), Draw disabled until recording, a stroke drawn while recording is in the clip. Test recordings deleted. Side-by-side pictures: scratchpad rec137/ost/c and rec137/ref.
- OST_QML_DIR=<checkout>/desktop/qml loads QML from disk (no 50-min rebuild for QML; bake shaders/*.frag with qsb into desktop/shaders first).

- 2026-11-21 (recD) rebased on desktop/foundation 7063948 (Main.qml harness-list conflict resolved), rebuilt on linuxlt, re-run on the compiled build: all effects and the 1280x720 clip as before; screen mode Draw stroke in the clip. Engine lib tests 850 passed. The scratchpad (tmpfs) was wiped by the PC restart, so the earlier reference/side-by-side PNGs and capture files are gone; the measurements are in these notes and docs/spec/messages-and-composer.md.
<!-- SECTION:NOTES:END -->
