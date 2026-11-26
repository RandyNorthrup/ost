---
id: TASK-0320
title: 'OneDrive Shared view: By you tab, filter pills, People chips'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T21:11:00Z'
updated_date: '2026-11-26T20:07:00Z'
labels:
  - onedrive
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0303 moved OneDrive's Shared ▸ With you and Browse files by People to OneDrive's own services with Teams' items and order. Teams' Shared view also has a By you tab (_api/web/onedriveshareditems?$top=1000), type filter pills and a place line under each name, and its People view shows each person's files as chips with a +N, where OST still lists a file count.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OneDrive Shared has With you and By you tabs listing what Teams lists, in Teams' order
- [x] #2 Shared's filter pills and People's file chips (+N) look and behave as Teams' do
- [x] #3 Shared's columns are Teams' (Name with its place line, Date shared, Shared by, Activity; no File size or Sharing)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' Shared (With you, By you, More filters) and People chips on winpc.
2. Backend: By you (onedriveshareditems), hidden files for the Hidden filter, shared_day for chips.
3. OneDriveView: tabs, pills, Spartan columns (Name+place, Date shared, Shared by, Activity), By you (Name, Modified by), People chips with OneDrive's fit rule and +n.
4. Harness --shared-files-test --shared-tabs; compare with Teams.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc 2026-11-26: Shared tabs With you / By you; By you = {personal}/_api/web/onedriveshareditems?$top=1000 in service order, Name (no extension, place line) + Modified by, 42fr:58fr, no pills. With you pills All, Folders, Word, Excel, PowerPoint, PDF, More (… Photos, Agent, Hidden). Columns Name, Date shared, Shared by, Activity (swmResponsiveBehavior). People chips: OneDrive's filePill fit rule (chars×5.2+64+pill from 50 within width-64-320-8; overflow file shortened if 8 chars fit; +n).
- Live on linuxlt (--shared-files-test --shared-tabs): With you = Teams' 8 rows, same order, columns; Videos pill = the 5 recordings; By you = Teams' 62 rows in Teams' order and names; People = OST Test 2 (2 chips + "+2"), OST Test 3 (2 chips) as Teams.
- Not built: the column header menus (Name ▾, Date shared ↓ ▾, Shared by ▾).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneDrive Shared and Browse by People now match Teams.

Changes:
- Shared has the With you / By you tabs. By you comes from `_api/web/onedriveshareditems?$top=1000`, in the service's order, with Name (and place line) and Modified by.
- With you has pills (All, Folders, Word, Excel, PowerPoint, PDF, More ▾ with Photos, Agent and Hidden) and the filter box. The columns are Name with the place line, Date shared, Shared by and Activity; File size and Sharing are gone.
- People shows file chips with the activity pill and "+n", using OneDrive's filePill fit rule, plus "Filter by person".
- Harness `--shared-files-test --shared-tabs`; docs/spec/onedrive-rows.md.

Tests: live as ost-test1 against Teams on winpc. With you has the same 8 rows, the Videos pill and By you's 62 rows match in Teams' order, and the People chips match.

Follow-up: TASK-0340 (column header menus).

PR #20.
<!-- SECTION:FINAL_SUMMARY:END -->
