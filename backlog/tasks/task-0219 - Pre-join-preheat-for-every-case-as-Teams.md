---
id: TASK-0219
title: Pre-join preheat for every case as Teams
status: To Do
assignee: []
created_date: '2026-11-17T08:21:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0215 left (docs/spec/call-and-meeting-window.md §1.8k): a channel Meet now pre-join and a pre-join opened while already in a call aren't preheated (they still read the calendar invitation); OST's preheat request keeps its own call modalities and doesn't send mediaDescriptions or aiVoiceConsent, and doesn't acknowledge the acceptance in its Trouter reply as Teams does; Teams desktop's own preheat and its dial-plan ECS flag weren't measured on winpc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every pre-join preheats as Teams does, with Teams' request fields, checked against Teams desktop on winpc
<!-- AC:END -->
