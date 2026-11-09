---
id: TASK-0068
title: '''You''re muted'' notice while speaking muted, as Teams'
status: To Do
assignee: []
created_date: '2026-11-09T05:25:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams shows a 'You're muted' notification when it detects your voice while your mic is off, and the in-meeting Accessibility pane (More ▸ Settings ▸ Accessibility settings) has a Muted notification switch for it (kept on the device). Its look and detection rules still need measuring: the anonymous guest client doesn't show it, and winpc joins test meetings without audio. The Accessibility pane's card stays hidden until this lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Speaking with the mic off shows Teams' notice, measured against a Teams client with audio (layout, wording, timing)
- [ ] #2 The Accessibility pane's Muted notification switch turns it on and off and is remembered on the device
<!-- AC:END -->
