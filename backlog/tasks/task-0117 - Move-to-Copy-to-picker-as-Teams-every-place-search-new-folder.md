---
id: TASK-0117
title: 'Move to / Copy to picker as Teams: every place, search, new folder'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-13T16:48:00Z'
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
- [x] #2 Search in the picker and New folder work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#3 (Rename's Suggested names) moved to TASK-0124, with the picker's view switch / Pin to Quick access and a folder's own command bar.
- Picker requests are numbered ("<tag><n>:<op>"); answers to older requests are dropped.
- 2026-11-12: search is down tenant-wide (Teams on winpc stuck loading; SharePoint search, Graph search and sharedWithMe answer 500-504), so search is covered by unit tests and the error path.

- Verified on linuxlt (--picker-test, --picker-live): My files, every place, More places cards, New folder (created, opened, deleted), stale answers dropped, search box/tabs/Location column and the error state.
- AC#2 left open only for search results: re-run --picker-test when the tenant's search answers again.

- 2026-11-13: search answers again. Measured Teams' search on winpc (CDP + its own query): it finds folders only, has a date filter and a Person filter, rows say "Created by:", and Location reads "My files" / site / "…'s OneDrive" with folders.
- OST now sends Teams' query and template through Graph /search/query (search_folders, date_filter_days, location), with the measured tabs, dates pill and menu, and the search grid; Location opens the folder.
- Verified on linuxlt (--picker-test): My files "Recordings" → Recordings @ My files; All files "ost" → team folders @ OST Test Team, Loop workspace @ My workspace; Last 7 days narrows; Location opened OST Test Team's library.
- Person filter and Location pictures moved to TASK-0128 (Teams' All files sign-in failed, so they couldn't be measured).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Move to / Copy to picker: every place, search and New folder as Teams.

Changes:
- Places: Shared, Favorites, Browse by People / Meetings, More places… (Shared libraries cards).
- Search as Teams' picker searches: folders only (Teams' KQL template), My files limited to your OneDrive's library, 25 by relevance, through Graph /search/query with SharePoint managed properties.
- Measured search UI: 16/600 tabs with the underline, the date filter pill and its menu (All dates … In the last year → LastModifiedTime from midnight UTC N days back), the results grid (Name with "Created by:", Modified in OneDrive's wording, Modified by, Location).
- Location built as OneDrive's code builds it ("My files", site title, "{name}'s OneDrive", folders, A › … › Z), tooltip with the path; a tap opens the folder.
- New folder in the picker; requests numbered so stale answers are dropped.

Tests:
- cargo test --lib (486 pass), incl. picker_search_asks_for_folders_as_teams_does, search_locations_read_as_onedrive_draws_them, search_hits_are_folders_with_their_location.
- --picker-test and --picker-live on linuxlt.

Follow-up: TASK-0128 (Person filter, Location pictures).
<!-- SECTION:FINAL_SUMMARY:END -->
