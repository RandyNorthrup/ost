---
id: TASK-0178
title: Resizable chat list as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T14:52:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' list width follows the window and can be dragged between 280 and 400 px; OST's is fixed at 320.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The list resizes and drags within Teams' limits, and the width is kept as Teams keeps it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (7d40c0a): default width by window (280/320/360 at 640/1280/1500), drag 280–400 keeping 68+320 for the rail and main area, arrow keys 20 px, double-click reset; saved as a share of the window on this device (Teams: localStorage teams-layout-slot-size-persistence, not synced). Checked at 1280 (320, 400, 280, 300, reset).
- Not covered: Teams' under-640 layout (OST's window minimum is 800).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The chat list resizes as Teams': window-dependent default, 280–400 drag limits, keyboard steps, double-click reset, width kept per device as a share of the window. Harness --chatlist-menu-test.
<!-- SECTION:FINAL_SUMMARY:END -->
