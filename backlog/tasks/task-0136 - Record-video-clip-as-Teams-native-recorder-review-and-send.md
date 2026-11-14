---
id: TASK-0136
title: 'Record video clip as Teams: native recorder, review and send'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-14T09:43:00Z'
updated_date: '2026-11-14T12:05:00Z'
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
- [ ] #5 Review editing as Teams: Trim, Split, Record more and Music
- [ ] #6 Backdrop (None, Upload, Blur, images and videos), Script, Draw and Effects as Teams
- [ ] #7 Verified side by side with Teams on winpc
- [ ] #8 Pausing a screen recording keeps its video and sound in step
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-14 research on winpc: Teams embeds Stream's StreamCameraEmbed.aspx (frame-ancestors: Microsoft sites only), so the recorder is native. Measured the camera, Record audio and Screen modes, the device menus, the recording pill, paused, review, trim, music, the close question and the compose card. No countdown.
- Built: VideoClipRecorder.qml (camera and screen recorded with QtMultimedia MediaRecorder at full rate; Record audio records the picture through ClipFrames: clipframes.cpp grabs the picture and feeds QVideoFrameInput); api::video_clips::{upload (client.ams_upload_video), clip_html, new_card_id}; Outgoing.ams_references; backend recorder_file / remove_recorder_file / save_recording / video_clip_upload / send_with_clip; ComposeBox clip card ("Processing...", Remove video clip, Re-upload video clip); "+" ▸ Record video clip; the clip end screen's "Reply with a video clip" now opens it.
- Qt 6.10 gotchas: the MP4 muxer stalls without an audio track (a muted microphone always goes in); the frame-input encoder stays paused until one pause/resume (done right after record); frames are timed by count (the newest picture is sent every 33 ms); the microphone must be open before recording.
- Verified: on linuxlt, Record audio (silent mic) 11.9 s and camera mode on test camera A 12.0 s at 30 fps; locally on Hyprland, screen mode through the portal picker (a kitty test window). OST TEST 136 (Record audio) was sent and plays in Teams on winpc (1280x720). OST TEST 137 (camera, test pattern) is stored and ready in AMS and the chat service; winpc Teams has not synced it yet.
- Known: in screen mode a pause leaves the video track longer than the audio (Qt's screen capture keeps its clock running).
<!-- SECTION:NOTES:END -->
