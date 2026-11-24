---
id: TASK-0033
title: 'Conversation header: tabs, find and participants'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T18:10:00Z'
updated_date: '2026-11-05T18:15:00Z'
labels:
  - desktop
  - chat
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The conversation header's tabs (Shared, Notes, Recap, Storyline) and buttons (find in chat, participants, chat details, more options) were drawn but did nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Shared lists the files and links shared in the chat and opens them
- [x] #2 Tabs OST cannot provide say so instead of doing nothing
- [x] #3 Find in chat searches the loaded messages and jumps between matches
- [x] #4 Participants lists the chat's members with their pictures and presence
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shared tab (files and links), honest placeholders for unsupported tabs, find in chat with stepping, participants list. Verified with --header-test captures (find: 25 matches for 'ost test').
<!-- SECTION:FINAL_SUMMARY:END -->
