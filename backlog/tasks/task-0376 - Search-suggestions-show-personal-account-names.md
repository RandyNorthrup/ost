---
id: TASK-0376
title: Search suggestions show personal-account names
status: To Do
assignee: []
created_date: '2026-11-28T00:04:00Z'
labels:
  - desktop
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0366 (PR #62): in the new search suggestions, a message whose other person is a personal (8:live:) account shows that person's raw Teams ID in its where line. TASK-0289 (PR #68) added the 8:live: name lookup (fetchTflProfiles); use it in src/api/autosuggest.rs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Search suggestions show the personal-account person's display name (and picture where shown), as Teams does
<!-- AC:END -->
