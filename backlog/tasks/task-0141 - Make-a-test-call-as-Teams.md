---
id: TASK-0141
title: Make a test call as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T21:47:00Z'
updated_date: '2026-11-16T23:39:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings ▸ Devices' "Make a test call" places Teams' echo test call (scenario UserInitiatedTestCall; OST's signaling already has create_echo_call): the test call window, the recorded message played back, and Teams' results (microphone, speaker, camera, network).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Make a test call in Settings ▸ Devices starts Teams' test call with Teams' call window
- [x] #2 The echo service plays your recording back and Teams' results summary shows
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (e07b90b, merged): Settings > Devices > Make a test call creates the Echo chat and starts Teams' group call with the bot (camera on, no Chat/People, "Echo"), ends when the bot leaves; Teams' results screen (Microphone, Speaker, Camera, Network) with Device settings and Close, from OST's own checks.
- Re-checked on the merged build: connected, ended when the bot left, results all "Connected", closed.
- Leftovers: TASK-0211.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Make a test call works as in Teams: the Echo bot call in Teams' call window, playback, the end when the bot leaves, and Teams' results screen with Device settings. Harness --test-call-test. Follow-up TASK-0211.
<!-- SECTION:FINAL_SUMMARY:END -->
