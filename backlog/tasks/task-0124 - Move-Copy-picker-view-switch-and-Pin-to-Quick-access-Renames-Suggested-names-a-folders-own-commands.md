---
id: TASK-0124
title: >-
  Move/Copy picker view switch and Pin to Quick access; Rename's Suggested
  names; a folder's own commands
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T23:05:00Z'
updated_date: '2026-11-13T02:09:00Z'
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
- [x] #2 A subfolder's command bar with nothing selected offers the folder's Share, Copy link, Download and Open in OneDrive as Teams does
- [x] #3 Quick access (OneDrive pane and the picker) lists Teams' recent and pinned libraries, with their tiles, the info tooltip and pin / unpin as Teams
- [x] #4 The picker's Navigation Pane button and Browse by chevron collapse their parts as in Teams
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

- Navigation Pane rail and Browse by fold measured on winpc (rail 68 wide, list at 98.67) and built; --picker-views-test captures both.
- Rename's Suggested names researched: Copilot via OneDrive's AugLoop LLM service; Teams itself fails ("Something went wrong.") for OST Test 1 today, so moved to TASK-0125. OST's Rename is now 240 tall like Teams' without that row (was 210).
- Noticed: Teams lists the "Shortcuts" special folder in My files and the picker; OST hides it (follow-up TASK-0126).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Files: a folder's own command bar, Quick access, and the Move/Copy picker's views and folding pane, as Teams.

Changes:
- Subfolder command bar with nothing selected: Share, Copy link, Download, Open in OneDrive for the folder itself; trail moves under it and the list starts at 144.67 (folder loads now return the folder item as `here`).
- Quick access (OneDrive pane and picker) from SharePoint: pins via SP.PinnedItems.GetItemsBy, recent via GetQuickAccessItems; acronym tiles, (i) tooltip, pin/unpin (AddItem/RemoveItem) with OneDrive's notices. New `api::quick_access`, `SiteTile.qml`.
- Picker views: List (size line, Activity from SharePoint rows), Compact List (File Size, Sharing; 32-tall rows), Tiles (folder tiles, video pictures with nameplate, file pictures); friendly dates and type icons.
- Picker Navigation Pane rail and Browse by fold.
- Rename dialog is 240 tall as Teams' without Copilot suggestions.

Tests:
- cargo test --lib (482 pass; quick_access parse/pin body tests)
- Harnesses on linuxlt: --folder-bar-test, --quick-access-test --quick-access-live (pin/unpin for real, left unpinned), --picker-views-test, --file-actions-test (Rename)

Follow-ups: TASK-0125 (Copilot Suggested names via AugLoop; failing in Teams today), TASK-0126 (Shortcuts folder).
<!-- SECTION:FINAL_SUMMARY:END -->
