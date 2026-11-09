---
id: TASK-0069
title: Call health pane as Teams (More ▸ Settings ▸ Call health)
status: To Do
assignee: []
created_date: '2026-11-09T05:55:00Z'
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
- [ ] #1 Settings ▸ Call health opens the pane laid out as Teams' (root and each 'View more' page), measured on winpc
- [ ] #2 Every metric shows OST's real values for the call (or '--' as Teams does when there's none), refreshed on Teams' schedule
<!-- AC:END -->
