---
id: TASK-0008
title: Replace ASCII art message borders with colorized backgrounds
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
Messages currently use ASCII box-drawing borders around each message, consuming too much vertical and horizontal space. Replace with alternating or colored background regions to visually separate messages without wasting lines on borders. This will increase message density and readability.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Messages are visually separated using background color instead of border characters
- [x] #2 No box-drawing borders around individual messages
- [x] #3 Sender name and timestamp are still clearly distinguishable from message body
- [x] #4 Message density is noticeably higher than before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-19 audit: criteria checked to match the Done status and final summary.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rewrote render_message_card() in messages.rs. Removed all ASCII box-drawing borders. Messages now use alternating background colors (Rgb(35,35,45) / Rgb(42,42,52)) with selected messages highlighted (Rgb(55,55,70)). Message density significantly increased. Verified via TUI tour -- clean borderless layout with many more messages visible per screen.
<!-- SECTION:FINAL_SUMMARY:END -->
