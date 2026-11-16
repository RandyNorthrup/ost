---
id: TASK-0141
title: Make a test call as Teams
status: To Do
assignee: []
created_date: '2026-11-14T21:47:00Z'
updated_date: '2026-11-16T04:52:00Z'
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
- [ ] #1 Make a test call in Settings ▸ Devices starts Teams' test call with Teams' call window
- [ ] #2 The echo service plays your recording back and Teams' results summary shows
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: The engine and CLI place Teams' Echo test call (src/calling/signaling.rs create_echo_call, call-test --echo). Nothing in the desktop app yet: no button, test-call window or results summary. (Audit 2026-11-16)
<!-- SECTION:NOTES:END -->
