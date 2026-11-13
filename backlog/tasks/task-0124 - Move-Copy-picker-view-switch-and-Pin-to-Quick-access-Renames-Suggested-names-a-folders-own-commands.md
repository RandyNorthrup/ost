---
id: TASK-0124
title: >-
  Move/Copy picker view switch and Pin to Quick access; Rename's Suggested
  names; a folder's own commands
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-12T23:05:00Z'
updated_date: '2026-11-13T01:39:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0117. Teams' Move/Copy picker has a view switch and a "Pin to Quick access" button; Rename shows Copilot's Suggested names (44 tall) when Copilot is available; and in a subfolder with nothing selected, Teams' OneDrive command bar offers Share, Copy link, Download and Open in OneDrive for the folder itself (docs/spec/file-actions.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The picker's view switch and Pin to Quick access work as in Teams
- [ ] #2 Rename shows Suggested names as Teams does when Copilot is available
- [x] #3 A subfolder's command bar with nothing selected offers the folder's Share, Copy link, Download and Open in OneDrive as Teams does
- [x] #4 Quick access (OneDrive pane and the picker) lists Teams' recent and pinned libraries, with their tiles, the info tooltip and pin / unpin as Teams
- [ ] #5 The picker's Navigation Pane button and Browse by chevron collapse their parts as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Folder bar: measure Teams' subfolder layout on winpc, return the folder item with its children, draw the bar/trail/list offsets, harness --folder-bar-test.
2. Picker view switch and Pin to Quick access: research on winpc (what Pin writes, view options), then build.
3. Rename Suggested names: research the Copilot request and its availability for OST Test 1, then build or record why not.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Folder bar done: measured on winpc (bar at 16 without card, trail at 96, list at 144.67; selection keeps the trail). Backend adds `here` (the folder item) to folder loads; OneDriveView draws the bar; --folder-bar-test verifies commands, layout, selection and Share for the folder.

- Picker views: List / Compact List / Tiles measured on winpc and built (Activity column from SharePoint rows in the picker's folder load; friendly dates; type icons; video tiles with nameplate). --picker-views-test.
- Quick access: new api::quick_access (GetItemsBy for pins, GetQuickAccessItems for recent; AddItem/RemoveItem). GetQuickAccessItems' PinnedDocumentLibraries stays empty after a pin, so pins come from GetItemsBy. Pane + picker rows with SiteTile, (i) tooltip, pin button, notices. --quick-access-test [--quick-access-live]; live pin/unpin verified and the test account left with nothing pinned.
<!-- SECTION:NOTES:END -->
