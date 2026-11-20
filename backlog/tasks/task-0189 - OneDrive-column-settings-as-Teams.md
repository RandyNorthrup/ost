---
id: TASK-0189
title: OneDrive column settings as Teams
status: To Do
assignee: []
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T09:04:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' column headers have a Column settings submenu; OST offers only Ascending and Descending.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Column settings (show/hide, width, move) work as in Teams and are kept as Teams keeps them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 measured on winpc (Teams' OneDrive app is OneDrive's spartan list, odsp-web-prod_2026-11-06.005):
  - Header menus: Name = Ascending/Descending | Column settings; Modified = Older to newer/Newer to older | Filter by | Column settings; Modified By = A to Z/Z to A | Filter by | Column settings; File size = Smaller to larger/Larger to smaller | Column settings; Sharing = Column settings only; Activity = no menu. Menus 232 wide, rows 36.
  - Column settings = Widen column / Narrow column only (Teams has no show/hide or move there). Widen/Narrow = current width (floored) +/-32.
  - Drag: 16x36 resize dividers centred on each column boundary (Name|Modified ... Sharing|Activity), 8 below the header top, ew-resize, hover line 1 px #605E5C 28 tall.
  - Kept on this device only, in the SharePoint origin's localStorage: key spcolumnsize-unsaved-{viewId}, value {"<column display name>":"<px>"}; no server call. Rendered width = max(stored, responsive width).
  - Responsive base widths (ODBMyFilesResponsiveBehavior + OneDrive's module 4377): DocIcon 40, Name 210-800, Modified 130-200, Modified By 130-260, File size 85-110, Sharing 75-110, Activity 113-550; spare width shared evenly; columns dropped by priority when too narrow. At a 1212 frame: 213.6/133.6/133.6/88.6/78.6/116.6.
  - Restored after: key removed, frame back to 100%.

- 2026-11-20 built: OneDriveView responsive widths (OneDrive's algorithm), header menus in OneDrive's words with Column settings ▸ Widen/Narrow, drag dividers, device setting oneDriveColumnWidths; harness --column-settings-test. Pending: run.

- 2026-11-20 verified (--column-settings-test at 1280x680): menus in OneDrive's words, Widen 141.27 -> 173, drag-set 200, Narrow under the responsive width stored but not shown, kept in oneDriveColumnWidths, reset. Open: Filter by (filters pane) not built.
<!-- SECTION:NOTES:END -->
