---
id: TASK-0035
title: 'Desktop: meeting reactions (React)'
status: To Do
assignee: []
created_date: '2026-11-06T04:53:00Z'
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
- [ ] #1 React sends like, heart, applause, laugh or surprised and Teams web shows it
- [ ] #2 Reactions from others show on their tile in OST
<!-- AC:END -->
