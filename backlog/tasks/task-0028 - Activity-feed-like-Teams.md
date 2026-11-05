---
id: TASK-0028
title: Activity feed like Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T17:15:00Z'
updated_date: '2026-11-05T17:26:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Activity (Ctrl+1) lists what happened to you: team adds, reactions to your messages, mentions and replies, missed calls and voicemail, with unread state and a badge on the rail. OST's Activity is a placeholder. Source: the 48:notifications stream (properties.activity).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Activity lists the notifications from 48:notifications with Teams' wording, avatar, time and preview, newest first, unread in bold
- [x] #2 Selecting an item opens its chat or channel beside the list; missed calls offer Call and Chat
- [x] #3 The rail shows the unread count, and opening Activity marks it read
- [x] #4 New notifications appear without a restart
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Activity feed from 48:notifications with Teams wording and layout, per-item read, badge from the feed horizon, live updates by push.

Tests: parse_feed unit test; --activity-test (open item -> chat beside, read, badge 0); live missed call from Teams web appeared within a second.
<!-- SECTION:FINAL_SUMMARY:END -->
