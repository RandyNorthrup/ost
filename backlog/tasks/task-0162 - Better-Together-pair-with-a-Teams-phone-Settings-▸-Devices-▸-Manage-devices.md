---
id: TASK-0162
title: 'Better Together: pair with a Teams phone (Settings ▸ Devices ▸ Manage devices)'
status: To Do
assignee: []
created_date: '2026-11-15T20:59:00Z'
labels:
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Manage devices page (Settings ▸ Devices ▸ Connected devices) lists the Teams phones paired with the PC (Better Together: betterTogetherPairedDevicesChangedEvent, deviceName, Connected, Disconnect via betterTogetherUnpairDevice). OST shows the page with an empty list (TASK-0159). Pairing needs a Teams phone, or an emulation of one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A paired Teams phone shows on Manage devices with Teams' name, status and Disconnect
- [ ] #2 Disconnect unpairs it as Teams does
<!-- AC:END -->
