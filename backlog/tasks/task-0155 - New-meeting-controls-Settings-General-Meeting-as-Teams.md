---
id: TASK-0155
title: New meeting controls (Settings > General > Meeting) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T08:36:00Z'
updated_date: '2026-11-16T21:56:00Z'
labels:
  - calling
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > General > Meeting has 'New meeting controls' (Meetings are easier than ever with a simplified, organized, and intuitive layout...), a switch that changes the meeting window to Teams' new controls layout. OST's call window has Teams' current controls. Measure the new layout on winpc (switch it on there, join a test meeting with camera and mic off) and build it as an alternative, with the setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings > General > Meeting shows 'New meeting controls' with Teams' text, saved where Teams saves it
- [x] #2 With it on, OST's meeting window uses Teams' new controls layout, matching Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (77a8b95, merged); spec docs/spec/new-meeting-controls.md.
- Setting: Teams Labs feature, device-local (WebView cache storage key), off by default; OST keeps newMeetingControls locally; turning it off opens OST's feedback form (to GitHub) where Teams opens Microsoft's.
- Layout: Teams' InlineCentered bar, React with Raise hand, More's grid / list / submenus, right-click Pin / Unpin / Move / Reset (local), narrow-window overflow order, compact bar under 480 px; Camera / Mic / Leave menus unchanged. Checked live in light, dark and High contrast against Teams on winpc (DOM and control-only shots).
- Also fixed: currentColor icons drew black in dark and High contrast.
- Leftovers: TASK-0208.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' New meeting controls in OST, with the setting.

- Settings > General > Meeting > New meeting controls (Teams' text), kept on the device as Teams does.
- With it on: Teams' centred bar, React with Raise hand, More's grid and submenus, pin/move/reset by right-click, Teams' overflow order and compact narrow bar. The old layout stays as "off".

Tests: layout engine unit tests; --join-new-controls live in three themes. Follow-up TASK-0208.
<!-- SECTION:FINAL_SUMMARY:END -->
