---
id: TASK-0305
title: Camera stays busy after turning it on in the pre-join screen
status: To Do
assignee: []
created_date: '2026-11-25T18:10:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots: turning the camera on in the meeting pre-join screen keeps the camera device open, so the camera then fails in the call ("Device or resource busy") and the "Your camera failed" bar stays until OST is restarted. Teams hands the camera from the pre-join preview to the call without an error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Turning the camera on in pre-join and joining shows your video in the call with no error, on linuxlt with a real or virtual camera
- [ ] #2 Turning the camera off and on in pre-join, in the call and after leaving never leaves the device open or the error bar stuck
<!-- AC:END -->
