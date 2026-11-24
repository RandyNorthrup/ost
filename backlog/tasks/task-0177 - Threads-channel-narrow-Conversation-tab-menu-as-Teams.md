---
id: TASK-0177
title: 'Threads channel: narrow ''Conversation'' tab menu as Teams'
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
At narrow widths Teams folds a threads channel's tabs into a 'Conversation ⌄' menu; OST uses its general '+N' overflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At Teams' breakpoint the tabs fold into Teams' menu, measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (7d40c0a): under a 640 px header the tabs fold into Teams' Posts/Conversation ⌄ menu in Teams' order (add-tab items, fixed tabs, movable tabs with their menus, Add a tab in chats). Checked at 960 wide on a channel and a chat (--tab-dropdown-test).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Narrow conversation headers fold their tabs into Teams' dropdown menu at Teams' 640 px breakpoint, in channels and chats, with Teams' item order. Harness --tab-dropdown-test.
<!-- SECTION:FINAL_SUMMARY:END -->
