---
id: TASK-0120
title: 'OneDrive app command bar as Teams: Sort, view switch, Details'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T15:58:00Z'
updated_date: '2026-11-12T18:56:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' OneDrive app title line (and its selection bar) has Sort ▾, the view switch (list, compact, tiles) and Details at the right; the column headers' chevrons sort too. OST's OneDriveView.qml shows the title and, with rows selected, the selection bar without them (docs/spec/onedrive-rows.md). Research each on winpc first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sort ▾ and the column headers sort the list as Teams does, with its menu
- [x] #2 The view switch offers Teams' views and each draws as Teams
- [x] #3 Details opens the details pane for the folder or the selection (with TASK-0115)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' OneDrive command bar controls are native in OST.

Changes:
- Sort ▾ (Type, Name, Modified, Modified By, File size; Ascending/Descending), sortable column headers with ↑/↓, folders first, kept for the session (OneDriveView.qml).
- View switch: List, Compact List (34 px rows, 20 px icons), Tiles (176 x 171 cells, folder art with counts, file pictures from Graph "medium" thumbnails, hover card and selection circle).
- Details on the title line and in the selection bar (pressed while open); with nothing selected it shows the folder's pane: name and its activity, worded per item with move halves and repeated edits merged (item_details::folder_feed, unit-tested).

Tests: cargo test --lib (474 pass); --sortview-test on linuxlt compared with Teams on winpc (sorted order, compact, tiles, folder feed).

Not yet: Column settings ▸ in header menus.
<!-- SECTION:FINAL_SUMMARY:END -->
