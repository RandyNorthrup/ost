---
id: TASK-0321
title: Camera stays open while OST is idle
status: To Do
assignee: []
created_date: '2026-11-25T22:56:00Z'
labels:
  - bug
  - privacy
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). Every running OST instance keeps the camera device (/dev/video0) open even when no call, preview or clip recorder is using it, so the camera can't be used elsewhere and may show as in use. Teams opens the camera only while it shows video.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST opens a camera only while a preview, call video, video effects preview or clip recording is active, and closes it within a second of the last one stopping
- [ ] #2 With OST idle (no call, no preview), no camera device is open (checked with fuser/lsof on linuxlt)
<!-- AC:END -->
