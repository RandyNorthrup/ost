---
id: TASK-0048
title: >-
  Call audio and devices as Teams: echo cancellation, noise suppression, device
  flyouts
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-08T22:57:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Calls P1 gaps (docs/parity/gaps-calls-meetings.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Echo cancellation, noise suppression (Auto/High/None) and gain control on the mic path
- [x] #2 Camera ▾ and Mic ▾ flyouts with device lists, meters and Teams' disabled-reason tooltips
- [x] #3 Switching devices during a call
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-07: Mic ▾ audio flyout done (devices, volume, level; mid-call switching; PipeWire device names). Camera ▾ flyout pending the user's OK to turn on winpc's C920 for measuring (Teams shows a live preview in it).

- 2026-11-08 (2fcc454): wideband Opus as Teams sends it (PCMU fallback), WebRTC AudioProcessing (AEC3, noise suppression, AGC) via a C++ bridge to webrtc-audio-processing-1, capture fixed for stereo-only sources (it returned clipped garbage when asked for mono), RTCP sender reports. Verified live in the test meeting (Opus both ways with guests; echo lowered in the processed mic). The Mic ▾ flyout's Noise suppression section (switch, "Background noise only", "Isolate your voice" needing a voice profile) and the Camera ▾ flyout remain for AC #2.

- 2026-11-08: Camera ▾ (preview, V4L2 camera list, switching mid-call verified with two loopback cameras) and Mic ▾ noise suppression + More audio settings, measured in Teams during a test call; Teams' disabled reasons for Camera/Mic. Backgrounds and Adjust brightness are TASK-0064; the settings panes are TASK-0062.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Call audio and devices now work as Teams':

- Wideband Opus (Teams web's offer and payload types), PCMU fallback, 48 kHz pipeline; RTCP sender reports.
- WebRTC AudioProcessing (AEC3, noise suppression, adaptive gain, high-pass) through a C++ bridge to webrtc-audio-processing-1; noise suppression switch in Mic ▾, kept in settings.
- Capture opens the device's own channels and mixes down (stereo-only PipeWire sources returned garbage when asked for mono).
- Camera ▾ as Teams (preview, V4L2 camera list, More video effects and settings); cameras switch mid-call; Mic ▾ device switching as before.
- Teams' disabled reasons on Camera and Mic.

Tests: audio_codec (Opus/PCMU round trips), apm (echo cancelled), webrtc_audio, rtp audio level; live in the test meeting with guests (Opus both ways, echo lowered, camera A → B → A).

Follow-ups: TASK-0062 (settings panes), TASK-0064 (background effects, brightness).
<!-- SECTION:FINAL_SUMMARY:END -->
