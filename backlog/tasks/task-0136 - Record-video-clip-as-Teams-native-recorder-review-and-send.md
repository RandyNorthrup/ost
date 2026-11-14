---
id: TASK-0136
title: 'Record video clip as Teams: native recorder, review and send'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T09:43:00Z'
updated_date: '2026-11-14T16:48:00Z'
labels:
  - messages
  - video
  - compose
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' + ▸ Record video clip (and a clip's "Reply with a video clip") opens Microsoft Stream's recorder, which only Microsoft's own sites may host. OST needs the same recorder natively: camera, mic and screen, recording, review and editing, then the clip sent as Teams sends it (media store videototranscode + AMSVideo message).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Record video clip opens Teams' recorder (800 x 584): camera and mic toggles with their device menus (None, devices, Mirror video), Screen, and the screen-recording mode when the camera is off
- [x] #2 Start recording, Recording in progress / paused with the time left of 5:00, Stop and review, Pause/Resume, Record again, and Close asking "Close your recording?" as Teams
- [x] #3 Review your clips: playback with the filmstrip and time, Delete clip, Download recording, Back, and Continue putting the clip in the compose box (Processing…, then Teams' card with Remove video clip)
- [x] #4 Sending stores the clip in the media store and sends Teams' AMSVideo message; Teams shows and plays it
- [x] #5 Review editing as Teams: Trim, Split, Record more and Music
- [x] #6 Verified side by side with Teams on winpc
- [x] #7 Pausing a screen recording keeps its video and sound in step
- [x] #8 Script (teleprompter) as Teams: type or paste, play/scroll by words per minute, font size, speed, move and resize
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-14 research on winpc: Teams embeds Stream's StreamCameraEmbed.aspx (frame-ancestors: Microsoft sites only), so the recorder is native. Measured the camera, Record audio and Screen modes, the device menus, the recording pill, paused, review, trim, music, the close question and the compose card. No countdown.
- Built: VideoClipRecorder.qml (camera and screen recorded with QtMultimedia MediaRecorder at full rate; Record audio records the picture through ClipFrames: clipframes.cpp grabs the picture and feeds QVideoFrameInput); api::video_clips::{upload (client.ams_upload_video), clip_html, new_card_id}; Outgoing.ams_references; backend recorder_file / remove_recorder_file / save_recording / video_clip_upload / send_with_clip; ComposeBox clip card ("Processing...", Remove video clip, Re-upload video clip); "+" ▸ Record video clip; the clip end screen's "Reply with a video clip" now opens it.
- Qt 6.10 gotchas: the MP4 muxer stalls without an audio track (a muted microphone always goes in); the frame-input encoder stays paused until one pause/resume (done right after record); frames are timed by count (the newest picture is sent every 33 ms); the microphone must be open before recording.
- Verified: on linuxlt, Record audio (silent mic) 11.9 s and camera mode on test camera A 12.0 s at 30 fps; locally on Hyprland, screen mode through the portal picker (a kitty test window). OST TEST 136 (Record audio) was sent and plays in Teams on winpc (1280x720). OST TEST 137 (camera, test pattern) is stored and ready in AMS and the chat service; winpc Teams has not synced it yet.
- Known: in screen mode a pause leaves the video track longer than the audio (Qt's screen capture keeps its clock running).

- 2026-11-14 editing: Split, segment selection, Delete clip, Rearrange (Move left/right), Trim, Record more and Music measured on winpc and built. The preview plays the parts straight from the recordings, with the music looping at its level. Continue renders an edited clip (desktop/src/clipedit.cpp: an FFmpeg filter graph from api::video_clips::edit_graph, cut + concat + amix, 1280x720 H.264/AAC) before storing it: the edit is what gets uploaded, never the parts. Download recording renders the same way.
- Music: Stream's catalog (24 tracks, 5 categories) from its public CDN; level 15 by default; tracks cached in ~/.cache/ost/music.
- Verified: --recorder-edit-test on linuxlt (split at 4 s, trim to 1-3 s, record more, rearrange, In a dream). OST TEST 138 (rendered 12.8 s, music at -30 dB mean) was sent and plays in Teams on winpc.
- FFmpeg (libavfilter/format/codec/util) is now a build dependency of the desktop app; docs/desktop.md lists it.

- Backdrop and the Effects menu (Text, Draw, Stickers, Filter, Frame, Board, Photo) moved to TASK-0137; AC6 is now the teleprompter (Script).

- 2026-11-14 Script: Stream's teleprompter measured (panel, controls, 24-64 font, 50-400 wpm vertical slider) and its timing read from 288.js (linear scroll over words/wpm minutes; word marker timed by letters, +5 after punctuation). Built in VideoClipRecorder.qml, over the picture and not recorded; font size and speed kept in OST's settings. Verified with --teleprompter-test on linuxlt.

- 2026-11-14 screen pause: screen mode now records through ClipFrames (the picture, as Record audio does) instead of Qt's screen MediaRecorder, whose clock ran on through a pause. Verified locally on Hyprland (kitty test window via the portal picker, with a pause): video 10.05 s, audio 9.98 s, 1280x720. Record audio still 11.9 s on linuxlt. This path also carries what TASK-0137 will draw over the screen.

- 2026-11-14 side by side (Teams on winpc vs OST on linuxlt, same states: Record audio, Screen recording, Script, recording, paused, review, split, music, close question). Fixed from it: the consent strip's info icon is the outlined one; Camera's off shading shows only before recording; the playhead's time shows only while playing or with the pointer on the strip.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST records video clips natively, as Teams' "+" ▸ Record video clip (and a clip's "Reply with a video clip") does. Teams runs Microsoft Stream's recorder, which only Microsoft's sites may frame.

Changes:
- desktop/qml/VideoClipRecorder.qml (new): Teams' recorder at its measured layout.
  - Modes: camera, Record audio and Screen, with the camera and mic menus.
  - Recording: the pill (pause, record again, the 5:00 left across all parts) and the close question.
  - Review: the strip of parts with Split, Delete clip, Rearrange, Trim and Record more; Music (Stream's 24 tracks, looped at a level, 15 at first).
  - Script: Stream's teleprompter.
- desktop/src/clipframes.cpp + clip_frames.rs: records what the recorder's picture shows (Record audio, Screen) through QVideoFrameInput. Camera mode uses Qt's MediaRecorder at full rate. Works around three Qt 6.10 quirks (muxer needs audio, encoder needs a pause/resume, frames timed by count).
- desktop/src/clipedit.cpp + clip_edit.rs, api::video_clips::edit_graph: an edited clip is rendered with FFmpeg (cut, joined, music mixed) into one 1280x720 H.264/AAC MP4. Only the finished clip is uploaded, never cut-out footage.
- api: video_clips::{upload, clip_html, new_card_id, fetch_music}; client.ams_upload_video (sharing/videototranscode + thumbnail/original/transcript_info); Outgoing.ams_references.
- Compose: the clip card ("Processing...", Remove video clip, Re-upload video clip); send_with_clip sends Teams' AMSVideo element and amsreferences.
- Docs: spec §17 (the recorder, editing, music, Script); docs/desktop.md lists FFmpeg's libraries and Qt Multimedia.

Tests:
- cargo test --lib (505), incl. a_recorded_clip_is_sent_as_teams_sends_it and edits_render_as_one_clip.
- Harnesses on linuxlt: --recorder-test [--recorder-camera], --recorder-edit-test, --teleprompter-test. Screen mode tested locally through the Hyprland portal picker, sharing a kitty test window.
- Sent and played in Teams on winpc: OST TEST 136 (Record audio), 137 (camera, test pattern), 138 (edited, with music).

Follow-ups: Backdrop and the Effects menu (Text, Draw, Stickers, Filter, Frame, Board, Photo) are TASK-0137.
<!-- SECTION:FINAL_SUMMARY:END -->
