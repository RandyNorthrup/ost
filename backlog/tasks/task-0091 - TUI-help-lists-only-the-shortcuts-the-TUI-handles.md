---
id: TASK-0091
title: TUI help lists only the shortcuts the TUI handles
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:39:00Z'
updated_date: '2026-11-10T15:41:00Z'
labels:
  - tui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The help overlay (?) lists keys the TUI doesn't handle: gg/G, /, r, e, d, +, @, Ctrl+P, Ctrl+R, Ctrl+N, Ctrl+T, Ctrl+, and F1–F5. Only Tab/Shift+Tab, arrows, j/k, 1–3, Enter, Esc, Ctrl+Enter, Ctrl+U, Ctrl+K, Ctrl+D, PageUp/PageDown, ? and q work (src/tui/app.rs). Users are misled into trying actions that do nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every shortcut in the help overlay works when pressed in the pane it names
- [x] #2 No shortcut the TUI doesn't handle is listed
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The help overlay now lists only the keys the TUI handles, grouped by where they work: Navigation, Panes, Anywhere, Compose, Search (Ctrl+K) and Help.

Removed: gg/G, /, r, e, d, +, @, Ctrl+P, Ctrl+R, Ctrl+N, Ctrl+T, Ctrl+, and F1–F5. None of them had a handler in src/tui/app.rs.

Added keys that work but weren't listed: j/k, PgUp/PgDn (debug log), Home/End, Backspace/Delete, and that any key closes the help.

Tests:
- New `the_help_lists_only_handled_keys` (the removed keys stay out; the handled ones are listed).
- Rendered live in tmux at 160×45: every key and description fits its column.
<!-- SECTION:FINAL_SUMMARY:END -->
