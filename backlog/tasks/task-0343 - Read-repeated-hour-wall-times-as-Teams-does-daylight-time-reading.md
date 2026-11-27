---
id: TASK-0343
title: Read repeated-hour wall times as Teams does (daylight-time reading)
status: In Progress
assignee:
  - '@time'
created_date: '2026-11-27T00:11:00Z'
updated_date: '2026-11-27T00:56:00Z'
labels:
  - dst
  - time
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0319 kept chrono's choice for a wall time in an hour that a DST change repeats: the standard-time reading (the later moment). Teams reads such times with JavaScript's Date, which takes the daylight-time reading (the earlier moment). This affects presence expiries (Today ends 23:59:59.999, This week starts Saturday 00:00) and OneDrive's day groups in zones whose clocks go back at midnight, e.g. America/Santiago. OST is a 1:1 Teams clone, so it should match Teams.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A wall time in a repeated hour reads at the daylight-time (earlier) moment, as Teams does
- [x] #2 Presence's Today expiry on a day whose clocks go back at midnight ends at the earlier 23:59:59.999, as Teams' does
- [x] #3 Tests cover the repeated hour in a normal zone (US Eastern) and in a zone that changes at midnight
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. clock::earliest: in a repeated hour take the offset in force before the change (jiff's Fold before), as JavaScript's Date does.
2. Tests: US Eastern repeated hour (clock and presence), Chile's midnight change (clock earliest, presence Today).
3. Run the affected tests in UTC, New York and Santiago on linuxlt; PR, CI, Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Follows TASK-0319's note: chrono read a repeated hour at standard time; Teams (JS Date) at daylight time.
- clock::earliest now uses the offset before the change; presence's never-expiry already did.
- Affected tests (clock, presence, item_details, list_rows, recaps; 43) pass with TZ=UTC, America/New_York and America/Santiago on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
When a DST change repeats an hour, OST now reads wall times in it as Teams does: the earlier moment, in daylight time (PR #28). TASK-0319 had kept chrono's standard-time reading.

Changes:
- clock::earliest uses the offset in force before the change. Presence's Today/This week expiries and OneDrive's start-of-day groups follow it, so in zones whose clocks go back at midnight (e.g. Chile) Today ends at the first 23:59:59.999, as Teams' does.

Tests:
- US Eastern repeated hour (clock, presence) and Chile's midnight change (clock earliest, presence Today).
- Affected engine tests pass with TZ=UTC, America/New_York and America/Santiago on linuxlt; CI green; Codex: no findings.
<!-- SECTION:FINAL_SUMMARY:END -->
