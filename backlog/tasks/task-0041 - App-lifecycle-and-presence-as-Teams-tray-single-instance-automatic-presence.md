---
id: TASK-0041
title: 'App lifecycle and presence as Teams: tray, single instance, automatic presence'
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
labels:
  - desktop
  - shell
dependencies: []
references:
  - docs/parity/gaps-shell-calendar-files.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Core shell gaps from docs/parity/gaps-shell-calendar-files.md (P1): OST can't be quit once 'keep running on close' hides it, a relaunch starts a second instance, and presence never changes on its own.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 System tray icon with Teams' tray menu (incl. Quit); close-to-tray as Teams
- [ ] #2 Relaunching OST brings the running instance forward
- [ ] #3 Presence goes Away when idle/locked/minimised and shows In a call / In a meeting / Presenting automatically, as Teams computes it
- [ ] #4 Do not disturb suppresses banners as Teams does (priority access aside)
- [ ] #5 Set status message dialog as Teams (expiry, show when people message me)
<!-- AC:END -->
