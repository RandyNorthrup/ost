---
id: TASK-0152
title: Record a voicemail greeting (Settings > Calls) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T05:45:00Z'
labels:
  - calling
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > Calls > Voicemail > 'Record a custom greeting' / 'Record a greeting' starts a call to your own voicemail (GraphQL startCall {conversation: {id: your user id}, isVoicemail: true}), where the voicemail system lets you record the greeting. OST's calling can't place that voicemail call yet, so the row is left out of the card until it can.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Voicemail shows 'Record a custom greeting' with Teams' 'Record a greeting' button above the greeting language
- [ ] #2 The button places a call to your voicemail as Teams does, where the greeting can be recorded, and the call can be ended normally
<!-- AC:END -->
