---
id: TASK-0012
title: Help popup does not fully cover underlying content
status: Done
assignee:
  - '@claude'
created_date: 2026-02-06 00:06
updated_date: '2026-11-10T15:36:00Z'
labels:
  - bug
  - tui
  - ux
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The help overlay (? key) renders over the messages pane but does not cover the full width of the content area. Message text bleeds through on both sides of the popup border, creating a visually confusing display. The popup should either cover the full content area width or use Clear widget to erase the background behind it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help popup fully obscures underlying message content
- [x] #2 No text bleeds through around the popup borders
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The help overlay (?) now hides everything between the header and the status bar: the whole content area is cleared, then the shortcuts box is drawn centered in it. Message text and sidebar entries no longer show on either side of it.

Changes:
- `help::render_help_popup` takes the content area, clears all of it, and centers the popup there (ui.rs passes the area between the header and status rows).

Tests:
- New `the_help_overlay_hides_everything_around_it` (TestBackend 160×45: no background text anywhere between the header and status rows).
- Checked live on linuxlt in tmux (ratatui 0.30): with a channel open, ? shows only the box.
<!-- SECTION:FINAL_SUMMARY:END -->
