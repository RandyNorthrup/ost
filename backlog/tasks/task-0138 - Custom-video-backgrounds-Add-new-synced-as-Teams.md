---
id: TASK-0138
title: Custom video backgrounds (Add new) synced as Teams
status: To Do
assignee: []
created_date: '2026-11-14T18:00:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Add new tile uploads your own background picture (360–2048 px, jpeg/jpg/png/bmp, aspect < 4, max 5) to AMS (itemType IMAGE; shown via views/imgpsh_fullsize_anim) or to the OneDrive folder "Microsoft Teams User Custom Video Backgrounds", and records it in the user preference userCustomVideoBackground ([{imageName, quickXorHash, id}]) so it follows you to every device; uploaded pictures can be removed. See TASK-0064's notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Add new picks a picture, checks Teams' requirements with Teams' error messages, uploads and lists it as Teams does
- [ ] #2 Custom backgrounds added in Teams show in OST and vice versa; removing one works both ways
- [ ] #3 Applying a custom background replaces your background in what OST sends
<!-- AC:END -->
