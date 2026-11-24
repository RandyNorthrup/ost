---
id: TASK-0179
title: >-
  Chat list ··· menu: Customize view, Your communities, Shift+Esc confirmation
  as Teams
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
OST's menu has Mark all as read and Collapse all only, and Shift+Esc marks all read at once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The ··· menu has Teams' items
- [x] #2 Shift+Esc asks first, with 'Don't ask again', as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (7d40c0a): Teams' ··· menu (Mark all as read split, Collapse all sections Alt+Q, Customize view, Your teams and channels, Your communities), 248 wide; Mark all as read covers channels. Shift+Esc asks first with Don't ask again (kept on the device). The dialog text was confirmed on Teams desktop on winpc 2026-11-16 (then Cancel).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The chat list's ··· menu has Teams' items and order, and Shift+Esc asks before marking all as read, with Teams' text and Don't ask again, as on winpc. Harness --chatlist-menu-test.
<!-- SECTION:FINAL_SUMMARY:END -->
