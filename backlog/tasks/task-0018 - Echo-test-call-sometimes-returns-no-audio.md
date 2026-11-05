---
id: TASK-0018
title: Echo test call sometimes returns no audio
status: To Do
assignee: []
created_date: '2026-11-05T03:22:00Z'
labels:
  - calling
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
About 1 in 5 Echo bot calls (call-test --echo --tone) gets ICE and signalling through but receives 0 RTP: the bot's RTCP SR shows pkt_count=0 for the whole call. In the one failure seen after the SSRC fix (2026-11-04), the bot's x-ssrc-range started at 1000; in every successful call it started at 1101 or higher. That may be coincidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Root cause of the silent calls is identified from logs or packet capture
- [ ] #2 10 consecutive Echo calls each return audio containing the echoed test tone
<!-- AC:END -->
