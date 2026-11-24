---
id: TASK-0074
title: Send-side bandwidth estimate for Call health's Teams send limit
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T10:13:00Z'
updated_date: '2026-11-11T18:10:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Call health's 'Teams send limit' (network-sent-bw-estimate) is Teams' send-side bandwidth estimate. OST has no send-side estimator, so the value shows '--'. A transport-wide/GCC-style estimator would fill it and could also drive the video encoder's bitrate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Call health's Teams send limit shows OST's live send-side estimate in a call
- [x] #2 The video encoder's bitrate follows that estimate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11 (69b4522): transport-wide sequence numbers on every RTP packet we send in meetings (extension 3), the processor's transport-wide feedback (RTCP 205/15) parsed, a GCC-style estimator (trendline delay with adaptive threshold, loss, AIMD from 600 kbps). Live: feedback arrives; the estimate reached ~1.4 Mbps with 720p test video; Call health's Teams send limit showed 1.33 Mbps; the encoder followed (455 → 600 kbps, then the processor's own cap).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now estimates its send bandwidth as Teams does.

Changes:
- src/calling/send_bwe.rs: header-extension stamping, transport-wide feedback parsing, GCC-style estimator; process-wide current estimate.
- webrtc_audio: audio and video packets stamped before SRTP; RTCP decrypted once and shared (receiver reports, keyframe requests incl. lone PLIs, feedback).
- webrtc_video: encoder bitrate = min(processor limit, (estimate − 64 kbps) × 0.85), changed in place.
- call_health: network-sent-bw-estimate shows the estimate.

Tests:
- 437 lib tests (extension, feedback parsing, sequence unwrap, estimator growth/cut, loss cut).
- Live meeting with the v4l2loopback test camera: estimate, Call health value and encoder bitrate observed.
<!-- SECTION:FINAL_SUMMARY:END -->
