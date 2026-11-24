---
id: TASK-0023
title: Message dates and dividers like Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T16:07:00Z'
updated_date: '2026-11-05T16:17:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams labels messages not from today with 'Yesterday 10:37 PM' or the date, draws a centred 'Today' (or date) divider between days, and a brand-coloured 'Last read' line where unread messages begin. OST shows only the time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Message headers show 'Yesterday <time>', weekday or date for older messages and only the time for today, matching Teams
- [x] #2 A centred day divider appears between messages from different days
- [x] #3 A 'Last read' line appears above the first message that arrived after you last read the chat
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams-style dates in the conversation.

- Relative header stamps (time / Yesterday / weekday / M/d / M/d/yyyy).
- Day dividers between days, spacing measured from Teams desktop.
- Last read line above the first message after the read position captured when the chat opened.
- Bare rounded images for picture-only messages (RoundedCorners canvas, renderer independent).

Tests: cargo test (mark_first_unread unit test); side-by-side renders vs Teams desktop on winpc; Last read verified with a fresh message from Teams web.

Follow-up: weekday/date formats for messages older than yesterday are from Teams conventions and should be re-checked against Teams desktop once the test chat has older history.
<!-- SECTION:FINAL_SUMMARY:END -->
