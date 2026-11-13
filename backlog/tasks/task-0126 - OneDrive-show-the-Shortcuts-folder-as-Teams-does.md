---
id: TASK-0126
title: 'OneDrive: show the Shortcuts folder as Teams does'
status: To Do
assignee: []
created_date: '2026-11-13T02:09:00Z'
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
- [ ] #1 My files and the picker list the Shortcuts folder exactly when Teams does, with Teams' icon
<!-- AC:END -->
