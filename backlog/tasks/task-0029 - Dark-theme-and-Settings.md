---
id: TASK-0029
title: Dark theme and Settings
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T17:44:00Z'
updated_date: '2026-11-05T17:44:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop offers Light, Dark and Follow operating system themes, and a Settings page (Ctrl+,) for its options. OST had only a light theme and no settings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings > Appearance offers Follow operating system theme, Light and Dark, applied at once and remembered
- [x] #2 Dark uses Teams desktop's dark colours (read from its Fluent tokens)
- [x] #3 Settings offers auto-start, keep running on close, what Enter does, read receipts, desktop notifications and audio devices, each of which takes effect
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Dark/light/system themes with Teams' measured tokens; Settings with General, Appearance, Chats and channels, Notifications, Devices and About, all functional. Tested with --settings-test and dark side-by-side vs Teams desktop.
<!-- SECTION:FINAL_SUMMARY:END -->
