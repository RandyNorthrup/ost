---
id: TASK-0150
title: >-
  Chat list reordering as Teams: drag and drop, and single pointer 'Start
  reordering'
status: To Do
assignee: []
created_date: '2026-11-15T05:37:00Z'
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
- [ ] #2 Settings > Accessibility shows 'Turn on single pointer controls' with Teams' text and icon (hand point), kept on this device
- [ ] #3 With it on, the chat list's item menu has 'Start reordering', which reorders without dragging as Teams does
<!-- AC:END -->
