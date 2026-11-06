---
id: TASK-0034
title: 'Desktop: screen sharing in calls and meetings'
status: To Do
assignee: []
created_date: '2026-11-06T04:53:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Share is the last greyed control on the call bar. Teams shares a screen as a second video stream (applicationsharing-video); OST needs Wayland capture (xdg-desktop-portal ScreenCast + PipeWire; Hyprland's portal is installed), H.264 encoding (exists) and Teams' content-sharing signalling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Share in a 1:1 call shows the picked screen or window in Teams web
- [ ] #2 Share in a meeting shows it to the other participants
- [ ] #3 Stop sharing ends the stream on both sides
<!-- AC:END -->
