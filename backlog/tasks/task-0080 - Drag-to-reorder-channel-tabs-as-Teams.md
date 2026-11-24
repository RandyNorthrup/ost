---
id: TASK-0080
title: Drag to reorder channel tabs as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T16:43:00Z'
updated_date: '2026-11-10T07:50:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lets you drag a channel's tabs into a new order (not the predefined ones), saved through the same pinned-tabs order as Move left/right. OST only has the menu moves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tabs that Teams lets you drag can be dragged, with Teams' drag feedback; predefined tabs can't
- [x] #2 A drop saves the order with Teams' single-PATCH order algorithm, and Teams shows the new order
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' drag (overlay, shifts, prohibited, Esc) on winpc via VNC + CDP
2. move_tab_to + "to" op
3. DragHandler per tab, overlay card, shifts, announcements
4. Harness; drop in OST Test Team General, check Teams, move back
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel tabs can be dragged into a new order as Teams does.

Changes:
- Conversation.qml: per-tab DragHandler for movable tabs; the slot empties, a card (shadow8, radius 4, 14/20 name) follows the pointer, movable tabs slide 250 ms, fixed tabs stay, Prohibited (12) over a fixed tab, Esc cancels; the new order shows at once until the list reloads; Teams' drag-and-drop announcements.
- src/api/tabs.rs: move_tab_to (one PATCH of the moved tab's order, shared with Move left/right).
- backend channelTabChange "to"; Main.qml --tab-drag-test harness; spec docs/spec/channel-tabs.md.

Tests:
- rtest tabs (9 passed).
- --tab-drag-test on OST Test Team General: over Shared shows Prohibited and no drop; Page dropped after Notes; Teams on winpc showed Posts, Shared, Notes, Page; dragged back and Teams showed the original order.
<!-- SECTION:FINAL_SUMMARY:END -->
