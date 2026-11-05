---
id: TASK-0031
title: Make the chat pane filters work
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T18:00:00Z'
updated_date: '2026-11-05T18:02:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Unread, Channels and Chats chips and the filter box (search icon in the Chat header) are visible but do nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Unread shows only chats and channels with unread messages; Channels only Teams and channels; Chats only chats; clicking a chip again clears it
- [x] #2 The filter box narrows the list to chats, channels and teams whose names match
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chips and name filter work (verified with --filter-test: unread/channels/chats/name cases).
<!-- SECTION:FINAL_SUMMARY:END -->
