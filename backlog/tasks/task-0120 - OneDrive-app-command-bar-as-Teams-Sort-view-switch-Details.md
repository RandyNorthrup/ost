---
id: TASK-0120
title: 'OneDrive app command bar as Teams: Sort, view switch, Details'
status: To Do
assignee: []
created_date: '2026-11-12T15:58:00Z'
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
- [ ] #1 Sort ▾ and the column headers sort the list as Teams does, with its menu
- [ ] #2 The view switch offers Teams' views and each draws as Teams
- [ ] #3 Details opens the details pane for the folder or the selection (with TASK-0115)
<!-- AC:END -->
