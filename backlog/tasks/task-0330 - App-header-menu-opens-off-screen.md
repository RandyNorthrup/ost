---
id: TASK-0330
title: App header menu opens off-screen
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T15:37:00Z'
labels:
  - bug
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The menu in a hosted app's header opens partly off-screen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app header menu opens fully on screen next to its button, as in Teams, at any window size
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce the header menu position (main view, app window)
2. Keep the menu right-aligned to the button however its width changes, and inside the window
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: WebApp's header menu set x = button width - menu.implicitWidth once, before opening; MenuPopup measures its rows again as it opens (onAboutToShow, for a font that loaded late), so a menu that came out wider kept its old x and its right part hung past the window's right edge (the wiki grab of Whiteboard's ··· menu).
- Fix: x bound to the button's right edge minus the menu's current width, and margins 4 so it never leaves the window at any size.
- Live (linuxlt, Whiteboard in the main window and in its own window): the menu opens under ··· with its right edge on the button's (as Teams); widening the open menu (minRowWidth 300) kept its right edge at the button (1273 of 1280) where the old x would have put it at 1457.
<!-- SECTION:NOTES:END -->
