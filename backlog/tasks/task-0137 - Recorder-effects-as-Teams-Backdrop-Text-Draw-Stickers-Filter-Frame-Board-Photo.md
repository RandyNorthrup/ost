---
id: TASK-0137
title: >-
  Recorder effects as Teams: Backdrop, Text, Draw, Stickers, Filter, Frame,
  Board, Photo
status: To Do
assignee:
  - '@claude'
created_date: '2026-11-14T15:44:00Z'
updated_date: '2026-11-21T01:26:00Z'
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
<!-- SECTION:NOTES:END -->
