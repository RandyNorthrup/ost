---
id: TASK-0138
title: Custom video backgrounds (Add new) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T18:00:00Z'
updated_date: '2026-11-14T19:51:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Add new tile adds your own background picture (360–2048 px, jpeg/jpg/png/bmp, aspect ratio under 4). Teams desktop keeps it on this device (LocalCache\Microsoft\MSTeams\Backgrounds\Uploads as <uuid>.jpeg plus a 280-wide <uuid>_thumb.jpeg), selects it, says "Background added.", and lists uploads in Show all right after Add new; each upload's ··· menu has Remove ("Background removed."). The AMS/OneDrive + userCustomVideoBackground path in Teams' code is for VDI only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add new picks a picture, checks Teams' requirements with Teams' messages, keeps it on this device and selects it, as Teams does
- [x] #2 Show all opens Teams' Backgrounds view (Back to all video effects) with your uploads after Add new, then the whole catalog
- [x] #3 An upload's ··· menu removes it as Teams does, and an upload chosen as your background replaces your background in what OST sends
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find how Teams desktop stores uploads (code + a live upload on winpc).
2. Native import (QImage) with Teams' checks; Rust list/add/remove; backend calls.
3. Add new tile, Show all view, ··· Remove menu, info bar; harness steps.
4. Verify on linuxlt in a call.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research: Teams desktop's uploadVideoBackgroundImage goes to the native customVideoBackgroundsService (local files); the AMS/OneDrive + userCustomVideoBackground preference path is VDI-only (isOptimizedVdiV2). A live upload on winpc wrote Backgrounds\Uploads\<uuid>.jpeg (1920x1080) + <uuid>_thumb.jpeg (280x158), selected it and showed "Background added."; uploads appear only in Show all after Add new; ··· → Remove deleted both files ("Background removed."). Test upload removed and test image deleted afterwards.
- Validation from the bundle: type image/*, width and height ≥ 360, width/height ≤ 4 (the 1800 px max check is behind a flag that is off on desktop); picker accept ".png, .jpeg, .jpg, .bmp".
- Built: desktop/src/vfxpicture.cpp (QImageReader, JPEG 90 + 280-wide thumb, alpha flattened on white), video_effects.rs uploads (uuid ids, ~/.local/share/ost/backgrounds/uploads), backend videoUploads/addVideoBackground/removeVideoBackground, EffectTile add kind + hover ring + ··· Remove menu, VideoEffectsPane Add new + Show all view + info bar (wraps).
- Verified on linuxlt (--video-effects-test --video-effects-call): add → selected and applied to the call video (Camera ▾ preview), too-small PNG → "Couldn't add background: Invalid image size.", Show all lists the upload after Add new, Remove → "Background removed." and None selected.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' Add new for video backgrounds: your own pictures, kept on this device as Teams desktop does, listed in Teams' Show all view and removable from their ··· menu.

Changes:
- Research corrected the task: Teams desktop stores uploads locally (Backgrounds\Uploads\<uuid>.jpeg + 280-wide thumb); the AMS/OneDrive sync is VDI-only.
- desktop/src/vfxpicture.cpp: Teams' checks (image, ≥ 360 px, width/height ≤ 4), JPEG + thumbnail.
- video_effects.rs: list/add/remove uploads (uuid ids) and play a chosen upload as the background; tests.
- Backend: videoUploads, addVideoBackground, removeVideoBackground.
- QML: Add new tile and file picker ("Custom files"), Show all view (back button, uploads after Add new, whole catalog), ··· → Remove, Teams' info bar messages, tile hover ring.
- Spec §3 Video effects updated.

Tests:
- cargo test -p ost-desktop video_effects (3)
- Live on linuxlt: add, too-small error, Show all, remove; the upload replaced the background in the call video
<!-- SECTION:FINAL_SUMMARY:END -->
