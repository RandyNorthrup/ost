---
id: TASK-0117
title: 'Move to / Copy to picker as Teams: every place, search, new folder'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-12T23:17:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's picker (FileActions.qml) has My files and Quick access libraries. Teams' also has Shared, Favorites, Browse by (People, Meetings), More places…, Search in <place>, New folder and the view switch (docs/spec/file-actions.md); Rename also shows Copilot's Suggested names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The picker lists Shared, Favorites, Browse by People / Meetings and More places… as Teams does
- [ ] #2 Search in the picker and New folder work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#3 (Rename's Suggested names) moved to TASK-0124, with the picker's view switch / Pin to Quick access and a folder's own command bar.
- Picker requests are numbered ("<tag><n>:<op>"); answers to older requests are dropped.
- 2026-11-12: search is down tenant-wide (Teams on winpc stuck loading; SharePoint search, Graph search and sharedWithMe answer 500-504), so search is covered by unit tests and the error path.

- Verified on linuxlt (--picker-test, --picker-live): My files, every place, More places cards, New folder (created, opened, deleted), stale answers dropped, search box/tabs/Location column and the error state.
- AC#2 left open only for search results: re-run --picker-test when the tenant's search answers again.
<!-- SECTION:NOTES:END -->
