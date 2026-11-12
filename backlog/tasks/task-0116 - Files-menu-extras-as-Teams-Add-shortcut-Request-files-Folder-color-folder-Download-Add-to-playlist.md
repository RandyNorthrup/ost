---
id: TASK-0116
title: >-
  Files menu extras as Teams: Add shortcut, Request files, Folder color, folder
  Download, Add to playlist
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-12T19:58:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rest of Teams' Files menu (docs/spec/file-actions.md): Add shortcut ▸ (Shortcuts, My files, Other locations), a folder's Request files and Folder color ▸, Download of a folder (a zip), and a video's Add to playlist. Research each on winpc first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add shortcut ▸ adds the item to Shortcuts, My files or another place as Teams does
- [x] #2 A folder's Request files and Folder color ▸ work as in Teams
- [x] #3 Download of a folder or of several selected items saves one zip as Teams does (OneDrive's media service transform/zip)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#4 zip download done: media service transform/zip with .driveAccessToken (RenderOptions 5691143 + browser UA); spec docs/spec/zip-download.md; harness --zip-test.

- AC#2 done: Folder color (stampcolor, codes 0-15, shades), Request files (ShareLink kind 6 role 8, email via emailData+peoplePickerInput, confirmation). Teams' "OST test 113" request link and OST's 114 were the same folder link; removed (v2.0 permissions show owner only).

- AC#1 Add shortcut done (v2.1 children of special/shortcuts | root | folder). Note: deleting the special Shortcuts folder by mistake during research; restored from the recycle bin (same id), only the test shortcut removed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rest of Teams' Files menu is native in OST.

Changes:
- Download of a folder or several items: one zip from OneDrive's media service (transform/zip) with the drive access token from RenderListDataAsStream, OneDrive's names and notices (src/api/zip_download.rs, docs/spec/zip-download.md).
- Folder color ▸: dot in the menu, OneDrive's 16-colour picker, foldercoloring/stampcolor with OneDrive's codes, folders drawn in their colour (list, Tiles).
- Request files: OneDrive's two-step dialog, ShareLink linkKind 6 role 8, optional email with people search, created/sent confirmation.
- Add shortcut ▸ Shortcuts / My files / Other locations (Pick a folder): v2.1 children of special/shortcuts, root or the folder; the special Shortcuts folder hidden as in Teams.

Tests: cargo test --lib (478 pass); --zip-test and --folder-extras-test [--folder-extras-live] on linuxlt, compared with Teams on winpc; all test zips, links, colours and shortcuts undone.

Moved out: Add to playlist (needs a test Stream playlist) is TASK-0123.
<!-- SECTION:FINAL_SUMMARY:END -->
