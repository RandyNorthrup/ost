---
id: TASK-0091
title: TUI help lists only the shortcuts the TUI handles
status: To Do
assignee: []
created_date: '2026-11-10T15:39:00Z'
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
- [ ] #1 Every shortcut in the help overlay works when pressed in the pane it names
- [ ] #2 No shortcut the TUI doesn't handle is listed
<!-- AC:END -->
