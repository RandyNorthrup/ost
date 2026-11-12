---
id: TASK-0116
title: >-
  Files menu extras as Teams: Add shortcut, Request files, Folder color, folder
  Download, Add to playlist
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-12T19:57:00Z'
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
- [ ] #3 A video's Add to playlist works as in Teams
- [x] #4 Download of a folder or of several selected items saves one zip as Teams does (OneDrive's media service transform/zip)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#4 zip download done: media service transform/zip with .driveAccessToken (RenderOptions 5691143 + browser UA); spec docs/spec/zip-download.md; harness --zip-test.

- AC#2 done: Folder color (stampcolor, codes 0-15, shades), Request files (ShareLink kind 6 role 8, email via emailData+peoplePickerInput, confirmation). Teams' "OST test 113" request link and OST's 114 were the same folder link; removed (v2.0 permissions show owner only).

- AC#1 Add shortcut done (v2.1 children of special/shortcuts | root | folder). Note: deleting the special Shortcuts folder by mistake during research; restored from the recycle bin (same id), only the test shortcut removed.
<!-- SECTION:NOTES:END -->
