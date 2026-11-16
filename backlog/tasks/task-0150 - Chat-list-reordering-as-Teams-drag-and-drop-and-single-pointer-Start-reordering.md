---
id: TASK-0150
title: >-
  Chat list reordering as Teams: drag and drop, and single pointer 'Start
  reordering'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T05:37:00Z'
updated_date: '2026-11-16T20:22:00Z'
labels:
  - chat-list
  - accessibility
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lets you reorder chats in Favorites and custom sections, and teams and channels, by drag and drop. Settings > Accessibility > 'Turn on single pointer controls' (clientPreferences simpleCollab.enableSinglePointReordering, on this device) adds 'Start reordering', an alternative to drag and drop in the chats and channels list. OST's chat list can't be reordered yet, so the Accessibility card is left out until this is built. Measure Teams' drag feedback, the Start reordering mode and where the order is saved (sections/favorites order, teamsOrder) on winpc first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chats in Favorites and custom sections, and teams and channels, can be reordered by drag and drop as in Teams, and the order is saved where Teams saves it (Teams on winpc shows the same order)
- [x] #2 Settings > Accessibility shows 'Turn on single pointer controls' with Teams' text and icon (hand point), kept on this device
- [x] #3 With it on, the chat list's item menu has 'Start reordering', which reorders without dragging as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (dd601ea): drag and drop in Favorites, custom sections and teams with Teams' visuals (overlay, faded row, 2 px drop line, Escape cancels, teams fold while dragging a team; channels don't reorder); chat order saved through Teams' section-reorder request (a restarted Teams on winpc showed OST's order); team order saved in Teams' user property and read back. Settings > Accessibility > Turn on single pointer controls (device-only) and Start reordering with Move Up / Move Down.

Left: confirm Teams shows OST's team order (not picked up within 7 s; not checked after a Teams restart); dragging a whole section and dragging a chat into another section; keeping teams folded after a team drag.
<!-- SECTION:NOTES:END -->
