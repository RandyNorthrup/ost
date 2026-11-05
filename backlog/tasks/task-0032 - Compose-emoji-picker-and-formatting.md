---
id: TASK-0032
title: 'Compose: emoji picker and formatting'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T18:10:00Z'
updated_date: '2026-11-05T18:10:00Z'
labels:
  - desktop
  - chat
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The compose box's emoji and format buttons did nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The emoji button opens a searchable picker with categories and recent emoji; picking inserts at the cursor
- [x] #2 Format shows a bar for bold, italic, underline, strikethrough and lists (Ctrl+B/I/U too); formatted messages arrive formatted in Teams, plain ones stay plain
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Emoji picker and rich-text formatting with a safe editor-HTML converter. Tested live (bold arrives in Teams web) and with unit tests.
<!-- SECTION:FINAL_SUMMARY:END -->
