---
id: TASK-0048
title: >-
  Call audio and devices as Teams: echo cancellation, noise suppression, device
  flyouts
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-08T04:07:00Z'
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
- [ ] #1 Echo cancellation, noise suppression (Auto/High/None) and gain control on the mic path
- [ ] #2 Camera ▾ and Mic ▾ flyouts with device lists, meters and Teams' disabled-reason tooltips
- [ ] #3 Switching devices during a call
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-07: Mic ▾ audio flyout done (devices, volume, level; mid-call switching; PipeWire device names). Camera ▾ flyout pending the user's OK to turn on winpc's C920 for measuring (Teams shows a live preview in it).
<!-- SECTION:NOTES:END -->
