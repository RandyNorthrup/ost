---
id: TASK-0118
title: >-
  OneDrive app rows as Teams: hover Share and favorite, selection, Activity,
  dates
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-12T16:12:00Z'
labels:
  - files
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' OneDrive app rows (filebrowser.aspx in Teams) have a selection circle, hover ···, Share and favorite star after the name, an Activity column ("You shared this file"), Teams' relative dates ("A few seconds ago", "5 days ago", "Sunday at 3:41 PM") and a selection toolbar (Open, Share, Copy link, Delete, ···, Sort, n selected, view, Details). OST's OneDriveView.qml has its own simpler table.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Rows show the selection circle and hover ···, Share and favorite as Teams
- [x] #2 The Activity column and dates read as Teams
- [x] #3 Selecting items shows Teams' toolbar and its actions work
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams' OneDrive rows on winpc (DOM, styles, network, OneDrive bundles)
2. SharePoint row data module (FriendlyDisplay, _activity, PrincipalCount, ifnew) joined to Graph items
3. Rows, selection and command bar in OneDriveView; FileActions acting on several items; copy jobs for several sources
4. Harness --onedrive-rows-test [--onedrive-rows-live] on linuxlt; spec and parity docs
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams' list is RenderListDataAsStream; FriendlyDisplay only appears for a browser User-Agent (OST sends Teams web's).
- Activity strings and type map from OneDrive's bundle (module 1411/1424); activity time uses the client wording (Sun at 3:41 PM).
- Sizes from OneDrive's formatter (26.0 KB, 7.66 MB), confirmed in Recordings.
- Multi-select Download in Teams is a server zip (media transform/zip): moved to TASK-0116 AC#4; OST saves each file meanwhile.
- Sort, view switch and Details: TASK-0120.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneDrive app rows now read and act as Teams' (OneDrive's own list in a frame).

Changes:
- src/api/list_rows.rs: asks SharePoint for the folder's RenderListDataAsStream rows (Modified.FriendlyDisplay, Modified, PrincipalCount, Created_x0020_Date.ifnew, _activity) and joins them to Graph's items; decodes FriendlyDisplay, words _activity as OneDrive does ("You shared this file", "SharePoint App shared with Randy Northrup + 1 other"), the activity time ("Yesterday at 10:37 PM", "Sun at 3:41 PM"), and words other views' times with the same rules. Unit tests use the rows seen in Teams.
- OneDriveView.qml: Teams' table (56/40/Name/136/136/91/81/119, 49 px rows), hover #EBEBEB and selected #E9EAF6 fills inset 8, selection circles and select all, the New mark, ···/Share/favorite after the name, OneDrive file sizes and file-type icons, Modified tooltip, Sharing glyph, Activity column; click selects, Ctrl+click adds, name or double click opens.
- Selection bar: Open ▾, Share, Copy link, Delete, ··· for one item (folder without Open); Delete, Add to favorites, Download, ··· (Duplicate, Move to, Copy to) for several; "✕ n selected" clears.
- FileActions.qml / backend: several items in one CreateCopyJobs (Duplicate names each), Delete? for these items, OneDrive's counted notices.

Tests:
- cargo test --lib (465 pass, incl. list_rows and copy_jobs)
- --onedrive-rows-test on linuxlt: rows match Teams' text exactly; bar commands and menus per selection
- --onedrive-rows-live: duplicated two files together (copies deleted), moved both into Attachments and back

Follow-ups: TASK-0120 (Sort, view switch, Details), TASK-0116 AC#4 (zip download of several items or a folder).
<!-- SECTION:FINAL_SUMMARY:END -->
