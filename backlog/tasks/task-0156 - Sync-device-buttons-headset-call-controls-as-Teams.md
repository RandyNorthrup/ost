---
id: TASK-0156
title: Sync device buttons (headset call controls) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T09:37:00Z'
labels:
  - calling
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Devices > Audio settings > 'Sync device buttons' (This lets you use all the buttons on your device. The Teams button will...): Teams handles a USB/Bluetooth headset's call buttons (answer, hang up, mute, Teams button) over HID telephony. OST doesn't read headset buttons yet; on Linux they arrive through hidraw / the HID telephony usage page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Devices shows 'Sync device buttons' with Teams' text, kept as Teams keeps it
- [ ] #2 With it on, a headset's answer, hang-up and mute buttons control OST's calls, and OST's mute state shows on the headset, as in Teams
<!-- AC:END -->
