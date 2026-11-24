---
id: TASK-0007
title: Use shorter human-readable timestamps on chat messages
status: Done
assignee: []
created_date: 2026-02-05 23:20
updated_date: '2026-11-20T01:22:00Z'
labels:
  - tui
  - ux
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Chat messages currently display raw ISO 8601 timestamps like `2026-01-29T14:34:22.9820000Z` which are hard to read at a glance. Replace with human-friendly relative or short formats, e.g. "14:34", "Yesterday 14:34", "Jan 29".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Messages from today show time only (e.g. '14:34')
- [x] #2 Messages from this week show day and time (e.g. 'Mon 14:34')
- [x] #3 Older messages show date in short form (e.g. 'Jan 29')
- [x] #4 No raw ISO 8601 timestamps visible in the messages pane
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-19 audit: criteria checked to match the Done status and final summary.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added format_timestamp() in messages.rs. Parses ISO 8601 strings and formats: today as "14:34", this week as "Mon 14:34", older as "Jan 29". Falls back to raw string on parse failure. Verified via TUI tour -- messages show "Jan 19", "Jan 22", "Jan 30" etc.
<!-- SECTION:FINAL_SUMMARY:END -->
