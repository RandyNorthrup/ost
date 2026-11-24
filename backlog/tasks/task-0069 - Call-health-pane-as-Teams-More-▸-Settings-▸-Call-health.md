---
id: TASK-0069
title: Call health pane as Teams (More ▸ Settings ▸ Call health)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T05:55:00Z'
updated_date: '2026-11-09T10:28:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' in-meeting Call health side pane: 'Your call is receiving data. Most metrics refresh every 15 seconds. Learn more', Last updated at, then Network (Round trip time, Received packet loss), Audio (Sent bitrate, Received Jitter), Video (sent/received bitrate, frame rate, resolution, codec, processing) and Screen Sharing cards, each with a 'View more … data' page. Root pane layout measured on winpc 2026-11-09: scratchpad pp/call-health-root-dump.txt (session 744c3998); metric data-tids such as network-send-rtt-avg, audio-nw-jitter-avg, video-send-current-bitrate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings ▸ Call health opens the pane laid out as Teams' (root and each 'View more' page), measured on winpc
- [x] #2 Every metric shows OST's real values for the call (or '--' as Teams does when there's none), refreshed on Teams' schedule
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research the pane in Teams' call-health bundles and measure it on winpc (scratchpad ch/spec.md).
2. Library calling::call_health: per-stream counters in the media path, a 15-sample sampler, Teams' formatters.
3. Backend: sample every second, call_health_json and call_health_refresh.
4. QML CallHealthPane (root plus four detail pages) and the More ▸ Settings ▸ Call health toggle.
5. Verify live in the test meeting against winpc, then docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Pane and counters built. Live runs on linuxlt in the test meeting: RTT 31-46 ms, received loss 0.00%, receive limit 0.6-1.6 Mbps; camera on gives 0.38 Mbps / 17 fps / 640 x 360 px / H264 sw; with Guest 1 unmuted the received jitter is 3.6-5.1 ms (Teams on winpc showed 4.36 ms).
- Bug found by the run: audio-received metrics stayed "--" because the counting sat behind playback; it now counts every audio packet that arrives.
- Bug found by the run (pre-existing): after a meeting join, a lobby admission or a group call start, callCanVideo/callCanShare were never set, so Camera and Share looked disabled. All three paths now set them.
- The send limit stays "--": OST has no send-side bandwidth estimator yet (follow-up task).

- Screen sharing verified locally on Hyprland, sharing the kitty OST-share-test window: 9.6 fps, 1280 x 686 px, H264 sw, RTT 34.8 ms, 171 packets. Received-share metrics run on the same counting as received video, which was verified live.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' Call health pane (More ▸ Settings ▸ Call health) with OST's real call metrics.

Changes:
- `calling::call_health`: per-stream counters (bytes, packets, sequence loss, RFC 3550 jitter, frame size and rate, RTT from RTCP report blocks) and a 15-sample sampler that reproduces Teams' aggregation and number formats ("29.00 ms", "0.00%", "40 Kbps", "1.25 Mbps", "30.00 fps", "1280 x 720 px", "742 packets").
- Media path: audio, camera and screen sharing count what they send and receive. Video now sends sender reports every second (`forward_video`, one forwarder for camera and share). The MCP bandwidth estimate is Teams' receive limit.
- Backend: samples every second, plus `call_health_json` and `call_health_refresh`.
- QML `CallHealthPane`: the root page and the Network, Audio, Video and Screen Sharing pages, laid out as measured on winpc. It has "--" where Teams shows it, ⓘ tooltips, and the "turn on" hints while media is off. It refreshes every 15 s and at once when the mic, camera or share changes.
- The Settings ▸ "Call health" / "Hide call health" toggle, with the Fluent Pulse icon, in every call.
- Fixes found while verifying:
  - Received audio was only counted when played.
  - Meeting joins, lobby admission and group calls never set callCanVideo/callCanShare, so Camera and Share looked disabled in meetings.

Tests:
- `cargo test --lib call_health` (4 tests) and `cargo test --lib ubar` (6 tests).
- Live, in the test meeting:
  - linuxlt: muted, camera on, the mic on with Guest 1 talking, each page.
  - Locally: sharing the kitty test window.
- Values were compared with Teams on winpc (received jitter 3.6-5.1 ms against Teams' 4.36 ms; RTT ~30-45 ms on both).

Follow-up: TASK-0074 adds a send-side estimator for the Teams send limit, which shows "--" until then.
<!-- SECTION:FINAL_SUMMARY:END -->
