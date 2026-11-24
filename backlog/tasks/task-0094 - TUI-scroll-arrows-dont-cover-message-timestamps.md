---
id: TASK-0094
title: TUI scroll arrows don't cover message timestamps
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:58:00Z'
updated_date: '2026-11-10T16:03:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010). The messages pane draws its scroll indicators (^ at the top, v at the bottom) in the last column, over the last character of the first and last visible timestamps: "04:2^" for 04:24 (threads/00.txt) and "Mon 09:1v" for Mon 09:14 (general/06.txt).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Timestamps are never overwritten by the scroll indicators
- [x] #2 The indicators still show when there is more to scroll
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The messages pane keeps its last column for the scroll indicators: message text and timestamps lay out one column narrower, so ^ and v never cover a character. "04:24^" now shows where "04:2^" did (OST threads test, live in tmux).

While older messages load (TASK-0093), the list stays on screen instead of being replaced by "Loading messages...".

Tests: new `scroll_arrows_never_cover_timestamps` (TestBackend; only arrows or blanks in the gutter, both arrows shown).
<!-- SECTION:FINAL_SUMMARY:END -->
