---
id: TASK-0135
title: 'Video clips in messages as Teams: card, player, download'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T07:03:00Z'
updated_date: '2026-11-14T07:03:00Z'
labels:
  - messages
  - video
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Record video clip sends an AMSVideo clip (stored and transcoded in the media store). OST showed nothing for it. Show Teams' clip card where it was written, play it in Teams' inline player (controls, speed, quality, shortcuts, full screen, end screen) and offer Download video.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A received clip shows Teams' card (poster, play circle, length, Options) where Teams places it, at Teams' size
- [x] #2 Play shows Teams' inline player: progress, skip, sound, captions, speed, Playback options (Quality from the clip's renditions, Keyboard shortcuts), full screen, and the end screen
- [x] #3 Options ▸ Download video saves Teams' MP4 as MicrosoftTeams-video
- [x] #4 Verified side by side with Teams on winpc with a clip recorded in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched on winpc 2026-11-14 with OST TEST 135 (a 16 s screen clip recorded in Teams, camera and mic off) in the OST Test 2 chat: Teams embeds Stream's recorder (StreamCameraEmbed.aspx), stores the WebM in AMS as sharing/videototranscode and sends `<video itemtype=AMSVideo data-duration=…>`.
- AMS: views/video is an H.264 MP4; video.mpd lists renditions (720/480/360/cellular); a rendition = videoSegment/0 + 1..n joined (ffprobe: 1280x720 and 854x480 play).
- Built: api::video_clips (manifest, renditions, playable), MessageView.videos + FlowPart.video (blank first paragraph kept, as Teams draws it), VideoClipCard.qml (QtMultimedia), backend video_clip_load/video_clip_download, poster caching.
- Verified on linuxlt with --videoclip-test [--videoclip-download]: card at Teams' x 792.3, 400x225; play, pause, speed (scrolls at 157 as Teams), options, Quality 480p keeps the position, shortcuts panel, ··· Download video (1280x720 MP4 saved, then removed), end screen.
- "Reply with a video clip" shows only once OST can record clips (the recorder is TASK-0085 AC4); editing your own clip message in OST does not keep the clip yet (Teams' behaviour unverified).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Video clips recorded in Teams now show and play in OST as they do in Teams.

Changes:
- src/api/messages.rs: `<video itemtype=AMSVideo>` parsed into MessageView.videos (id, MP4, poster, data-duration, size); the clip keeps its place in the flow (FlowPart.video), with the blank first paragraph Teams draws above it; its "Video-Clip" fallback text is dropped; a clip alone reads "Video Clip".
- src/api/video_clips.rs (new): the DASH manifest's renditions (one per height) and a playable MP4 — Teams' own, or a rendition's init + media segments joined.
- desktop/qml/VideoClipCard.qml (new, QtMultimedia): Teams' card (poster, play circle, length, hover Options ▸ Download video) and inline player (progress, ±10 s, sound, captions, speed menu, Playback options ▸ Quality / Keyboard shortcuts, full screen, Alt-key shortcuts, end screen with Play again).
- backend: video_clip_load (cached per quality, owner-only) and video_clip_download ("MicrosoftTeams-video.mp4", honours Ask where to save); clip posters cached with the messages.
- Conversation.qml: clips in the message flow with Teams' 2 px margins; --videoclip-test harness; icons skip-back-10, skip-forward-10, speaker-mute, replay, video-clip (Fluent, MIT).
- docs/spec/messages-and-composer.md §17 "A video clip in a message"; docs/desktop.md lists Qt Multimedia.

Tests: cargo test --lib (503 pass, incl. video_clips_show_where_teams_put_them, a_clips_qualities_are_its_renditions); --videoclip-test on linuxlt.

Follow-ups: "Reply with a video clip" waits for the recorder (TASK-0085).
<!-- SECTION:FINAL_SUMMARY:END -->
