---
id: TASK-0097
title: TUI shows channel post subjects
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:58:00Z'
updated_date: '2026-11-10T16:05:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010). In OST threads test, OST TEST 88 and 89 were posted with subjects ("OST TEST 88 subject", "OST TEST 89 subject from OST"). The TUI shows only their bodies (threads/00.txt). Posts-layout announcements and subjects are missing the same way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A message with a subject shows the subject above its text, emphasized
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel post subjects show in the TUI: in bold, on their own line above the text.

- `MessageInfo` carries `subject` (from the desktop's message reader).
- The messages pane wraps it and draws it bold before the body.

Tests: new `subjects_show_bold_above_the_text`. Live in tmux, OST threads test shows "OST TEST 88 subject" over "OST TEST 88 body" and "OST TEST 89 subject from OST" over its body.
<!-- SECTION:FINAL_SUMMARY:END -->
