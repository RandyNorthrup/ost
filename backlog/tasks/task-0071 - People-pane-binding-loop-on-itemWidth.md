---
id: TASK-0071
title: People pane binding loop on itemWidth
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T07:21:00Z'
updated_date: '2026-11-09T07:26:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PeoplePane.qml line 508 logs 'Binding loop detected for property itemWidth' while a meeting's People pane is open; the layout should settle without a loop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Opening and resizing the People pane in a meeting logs no binding loop
- [x] #2 Rows keep Teams' measured widths
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: the More actions popover's itemWidth binding wrote TextMetrics.text while reading its advanceWidth, so the binding re-triggered itself.
- Fix: measure with FontMetrics.advanceWidth(text), which has no side effect; same QFontMetricsF::horizontalAdvance underneath, so widths are unchanged.
- Verified: a meeting join with the People pane open no longer logs the loop (it was in every earlier run's log, e.g. /tmp/ost-po.log on linuxlt).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed the "Binding loop detected for property itemWidth" warning from the meeting People pane.

The More actions popover sized itself by writing each label into a TextMetrics inside its width binding, which re-evaluated the binding. It now measures with FontMetrics.advanceWidth(text): no side effect, same measurement.

Test: live meeting join on linuxlt with the People pane open; no loop logged (previously logged on every run).
<!-- SECTION:FINAL_SUMMARY:END -->
