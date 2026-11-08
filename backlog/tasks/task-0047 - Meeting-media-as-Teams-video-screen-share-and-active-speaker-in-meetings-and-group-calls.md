---
id: TASK-0047
title: >-
  Meeting media as Teams: video, screen share and active speaker in meetings and
  group calls
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-08T11:29:00Z'
labels:
  - calls
  - meetings
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Calls/meetings P1 gaps (docs/parity/gaps-calls-meetings.md): meetings and group calls are audio-only in OST. Continues TASK-0034 #2 / TASK-0036 #2.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Video tiles in meetings/group calls (subscriptions via the media processor), self view, Teams' grid fitting
- [x] #2 Active speaker from Teams' speaker updates drives Speaker view
- [x] #3 Share and receive screen share in meetings and group calls
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Data channel: keep the OpenSSL DTLS session after the handshake and run SCTP over it (sctp-proto, sans-IO); open the "main-channel" data channel (DCEP, RFC 8832), binary messages.
2. MCP client (new src/calling/mcp.rs): 16-byte header framing, syn/ack, 1 s heartbeats, bwe, sr/sr_res with sequence numbers, dsh, vdclc; unit tests from the captured bytes.
3. Meeting offer as Teams: audio, main-video (camera), receive slots (main-video, recvonly), share line, x-data with x-data-protocol:sctp; mediaDescriptions in the join; answer the MP re-offers on the negotiations link with the same lines.
4. Receive slots: one H.264 receiver per slot keyed by SSRC range; map slot to participant through the source requested (sourceId from the roster, CSRC check).
5. Subscriptions: request roster participants whose main-video is sending into free slots (as Teams: fmtParams objects), release on leave/camera off; re-request on re-offer.
6. Call window: video tiles in the meeting grid (Teams grid fitting), self view; active speaker from dsh.
7. Verify live on linuxlt with the two guests (cameras on/off, join/leave) and compare with Teams on winpc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-07: Meeting client offers with video are accepted (Skype model: one main-video line, SSRC range, x-data line in the re-offer). Source requests over controlVideoStreaming / applyChannelParameters (202) and RTCP VSR got no video. Teams desktop sends none over HTTP, so its requests ride the media stack (likely x-data). Details in docs/spec/meeting-video.md; experiment code in git stash "TASK-0047 meeting-video experiments".

- 2026-11-07 (later): Implemented Teams' media control plane natively: SCTP data channel over the call DTLS (sctp-proto), MCP client, multi-slot meeting offer, slot routing by SSRC range, roster seeded from the join response. Live: both guests' cameras show in OST's meeting tiles (sr_res ok). Remaining: dsh/active speaker (capture its shape), Teams' tile look and grid fitting, video in the speaker strip, our camera into meetings (vdclc/simulcast), screen share in meetings.

- 2026-11-07: Quality: transport-cc feedback (twcc.rs) lifts the processor's estimate; 960x540 layers arrive (was 284x160). Gallery rebuilt to Teams' measured 16:9 layout (MeetingTile.qml), self first, name tags, voice-level outline from MCP dsh. Remaining: Speaker-view strip videos, our camera into meetings (vdclc layers), screen share in meetings, voice-level from audio levels rather than dsh alone.

- 2026-11-08: Sending in meetings as Teams does: camera and share lines sendrecv from the join, switched by UpdateMediaDescriptions only (both lines each time; share sendonly + negotiationTag "<callId>;ss_<n>"). Joins of an ongoing call use its id as chain id (thread liveness conversationId). controlVideoStreaming events (a viewer starts watching our screen) cap the encoder and force a keyframe. The processor answers H.264 as 42C01E; recognising it makes the share go out with the answer's PT 107 (was 102, dropped). Live from a Teams web guest: OST's shared window shown, then gallery on stop; camera on then off. Commit 446b44f.
- Still open for #3: a live check in a group call (same code path as meetings). Also open: voice-level outline from audio levels, gallery pages beyond the gallery size.

- 2026-11-08 (group call): Meet now in "OST group test" with Randy's Teams web (camera and mic off): OST's shared kitty window showed in Teams web (controlVideoStreaming capped the encoder as the bandwidth rose); Randy's shared example.com tab showed in OST's presenting layout, twice in a row. Logs once per video stream where it is routed.
- Gallery pages (gallery size, ‹ n/m ›) and Teams' name tags (12 px, guest glyph, filled mic-off), measured on winpc: commit 58fb147. Voice-level outline from the mix's CSRCs: 7c6c7e0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meetings and group calls now carry video, screen sharing and the active speaker, as Teams does.

Receiving:
- The media control plane (SCTP data channel over the call's DTLS; MCP framing; syn/ack/heartbeat; source requests; vdclc; dsh). Nine receive slots plus the sharing line, routed by answered SSRC range.
- Transport-wide congestion control feedback, so the processor sends 960x540 layers.
- Teams' gallery (16:9 fitting, pages of the gallery size with ‹ n/m ›), Speaker view, the View menu, room mode, the presenting layout and Pop out.
- The voice-level outline from the mix's CSRCs; Speaker view from dsh.

Sending:
- The camera and sharing lines are offered sendrecv and switched with UpdateMediaDescriptions only (share sendonly, negotiationTag "<callId>;ss_<n>").
- Joins of an ongoing call use its id as the chain id.
- controlVideoStreaming and vdclc cap the encoder and ask for keyframes.
- The processor's 42C0xx H.264 profile is recognised.

Tests:
- Unit tests for SCTP/DCEP, MCP, twcc, descriptions, control events, profiles and CSRC tracking.
- Live in the test meeting with up to four Teams web guests and winpc: cameras, shares and speaking both ways, plus gallery pages.
- Live in a group call (Meet now with Teams web): shares both ways.

Spec: docs/spec/meeting-video.md.

Follow-ups: TASK-0058 (others' own mute state), TASK-0059 (your mic waveform).
<!-- SECTION:FINAL_SUMMARY:END -->
