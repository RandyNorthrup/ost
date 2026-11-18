---
id: TASK-0223
title: Bluetooth headset buttons and unknown-vendor headsets as Teams
status: To Do
assignee: []
created_date: '2026-11-18T04:41:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0156 left: Bluetooth (HFP) headset call buttons aren't handled; a headset from a vendor Teams doesn't list only gets mute unless its USB UCQ string is read, which needs access to /dev/bus/usb; the 'Transfer controls to this app' button and prompt weren't clicked through live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Bluetooth headset's answer, hang-up and mute buttons control OST's calls as in Teams, verified live
- [ ] #2 An unknown-vendor USB headset whose UCQ string says it's a headset gets full call controls, as Teams
- [ ] #3 'Transfer controls to this app' and Teams' transfer prompt work between two OST instances, verified live
<!-- AC:END -->
