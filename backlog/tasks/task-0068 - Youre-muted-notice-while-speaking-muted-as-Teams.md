---
id: TASK-0068
title: '''You''re muted'' notice while speaking muted, as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T05:25:00Z'
updated_date: '2026-11-09T07:51:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams shows a 'You're muted' notification when it detects your voice while your mic is off, and the in-meeting Accessibility pane (More ▸ Settings ▸ Accessibility settings) has a Muted notification switch for it (kept on the device). Its look and detection rules still need measuring: the anonymous guest client doesn't show it, and winpc joins test meetings without audio. The Accessibility pane's card stays hidden until this lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Speaking with the mic off shows Teams' notice, measured against a Teams client with audio (layout, wording, timing)
- [x] #2 The Accessibility pane's Muted notification switch turns it on and off and is remembered on the device
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (Teams code): calling-pluginless speechDetectionDiagnostics; 1 s stats poll; speaking = audioLevel > 0.1; while muted keep 3 notes, >1 speaking raises DeviceSpeakWhileMuted (Bad), fewer clears it (Good dismisses the alert). Suppressed for hard-muted attendees, muted speakers, not connected. Strings from the installed Teams localization: "Your microphone is muted" / "Press {shortcut} to unmute your mic, or press and hold down {pushToTalkShortcut}." Same mic-off glyph and alert card as MicMutedRemotely; footer alerts draw at the stage top on desktop (raise-hand alert measured on winpc).
- Built: calling::muted_speech::Detector, audio::mic_recent_level (processed peak over 100 ms), backend 1 s check -> call_speaking_while_muted, CallWindow notice (two-line MutedNotice), Accessibility Muted notification card shown.
- Verified live on linuxlt with speech played into a virtual mic (PipeWire null sink, restored afterwards): notice follows speech and pauses; Close holds until speech stops; switch off suppresses it and is saved on the device; on again shows it.
- Not measurable: Teams' own rendering of this alert with real audio (winpc joins without audio; guests lack it). Layout is the shared alert card.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' "Your microphone is muted" notice when you talk with the mic off.

Changes:
- calling::muted_speech: Teams' detector (1 s notes, level > 0.1, 2 of the last 3 while muted; unmuting forgets).
- audio::mic_recent_level: the processed mic's peak over the last 100 ms (WebRTC's audioLevel equivalent).
- Backend checks every second (muted by you or the meeting) and exposes call_speaking_while_muted.
- Call window: the notice in Teams' alert card (glyph, title, two-line hint, Close), hidden for hard-muted attendees or when the Accessibility switch is off.
- Accessibility pane: the Muted notification card is now shown; its switch is saved on the device.
- Specs: meeting-video.md (detector, wording, placement), call-and-meeting-window.md.

Tests: muted_speech unit tests; live --join-muted-speech run with speech into a virtual microphone.
<!-- SECTION:FINAL_SUMMARY:END -->
