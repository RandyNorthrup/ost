---
id: TASK-0026
title: Title bar like Teams desktop
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T16:07:00Z'
updated_date: '2026-11-05T16:54:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop's title bar has back/forward history arrows, 'Search (Ctrl+E)' with Ctrl+E focusing it, the settings-and-more menu, your avatar, and its own minimise/maximise/close buttons; OST shows the web variant (app launcher, Ctrl+Alt+G hint) and no window controls.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Back and forward arrows move through the views and chats you visited
- [x] #2 The search box reads 'Search (Ctrl+E)' and Ctrl+E focuses it
- [x] #3 The window draws its own minimise, maximise/restore and close buttons and can be dragged and resized like Teams
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams desktop title bar: sidebar toggle, back/forward history, Search (Ctrl+E) / Ctrl+G, settings-and-more, profile, own window buttons on a frameless, draggable, resizable window (OST_SYSTEM_FRAME=1 opts out). Fluent presence badges.

Tests: --nav-test history run; title bar within ~1% of Teams pixels at 1280x680@1.5.
<!-- SECTION:FINAL_SUMMARY:END -->
