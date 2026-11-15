---
id: TASK-0158
title: Automatically adjust camera controls as Teams
status: To Do
assignee: []
created_date: '2026-11-15T09:37:00Z'
labels:
  - devices
  - video
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Devices > Video settings > 'Automatically adjust camera controls' with 'Open camera settings' (Some settings might not be available for all camera types.): Teams lets the camera's own auto exposure / white balance / focus run, or opens the camera's settings. On Linux these are V4L2 controls.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Devices shows the switch, the 'Open camera settings' link and Teams' note
- [ ] #2 The switch turns the camera's automatic controls on or off (V4L2), and the link opens OST's camera settings for the controls the camera offers
<!-- AC:END -->
