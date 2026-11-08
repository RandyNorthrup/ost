---
id: TASK-0035
title: 'Desktop: meeting reactions (React)'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-08T04:20:00Z'
labels:
  - desktop
  - calling
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams sends meeting reactions as proxied messages (type Reaction) over the conversation broker (links.subscribe / brokerPublish), which OST doesn't subscribe to; reactions from others never reach OST's trouter callbacks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 React sends like, heart, applause, laugh or surprised and Teams web shows it
- [x] #2 Reactions from others show on their tile in OST
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting reactions as Teams desktop.

- React menu measured on winpc (five 32 px buttons, Teams' 24 px V2 pictures).
- Send: proxied "Reaction" message to the conversation's sendMessage link (scope all, values[{id,name,count 1}]).
- Receive: conversation/receiveMessage/ events; shown on the sender's tile (84 px V4 picture, centred, top at mid-tile, 4.25 s).

Tests: unit tests for the send body and incoming parsing; live: Teams desktop on winpc showed OST's Like, and OST showed a guest's Like.
<!-- SECTION:FINAL_SUMMARY:END -->
