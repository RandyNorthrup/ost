---
id: TASK-0126
title: 'OneDrive: show the Shortcuts folder as Teams does'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T02:09:00Z'
updated_date: '2026-11-13T02:26:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lists My files' special 'Shortcuts' folder (0 items, with OneDrive's shortcut folder icon in the files list and a plain folder in the Move/Copy picker), seen on winpc on 2026-11-12. OST hides it (the specialFolder filter in drive::parse_items, added in TASK-0116 after the folder appeared). Check when Teams shows it (e.g. only once a shortcut was ever added) and match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 My files and the picker list the Shortcuts folder exactly when Teams does, with Teams' icon
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- OneDrive has no rule hiding the Shortcuts folder: it is ProgId AddToOneDrive.SpecialFolder and only gets the companyfolder icon. Teams lists it in My files and the picker (seen on winpc 2026-11-12); the earlier "Teams hides it" came from a stale Teams view.
- Removed the specialFolder filter in drive::parse_items; DriveItem.special carries the special folder name; OneDriveView draws ft-companyfolder-32/20 for it. Picker keeps the plain folder, as Teams.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneDrive's Shortcuts folder is listed again, as Teams lists it.

- drive::parse_items no longer drops the special Shortcuts folder; DriveItem gains `special` (Graph specialFolder name).
- The files list draws Fabric's companyfolder icon for it (Teams' icon); the Move/Copy picker keeps a plain folder, as Teams does.
- Specs: onedrive-rows.md, file-actions.md (Add shortcut).

Tests: cargo test --lib (parse test now expects the Shortcuts folder); --folder-bar-test capture of My files on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
