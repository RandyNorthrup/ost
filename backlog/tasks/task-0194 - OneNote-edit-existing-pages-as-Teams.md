---
id: TASK-0194
title: 'OneNote: edit existing pages as Teams'
status: Done
assignee: []
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T18:59:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's OneNote app reads, creates and deletes pages but can't edit one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An existing page can be edited and saved as in Teams' OneNote app
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20: Teams desktop's OneNote app is its personal page (0d820ecd staticTab MyNotebook, m365.cloud.microsoft officeunihost, full screen); OST hosts it the same way instead of its native OneNote view.

- 2026-11-20 done in OST: the app bar's OneNote is Teams' personal page in OST's host (native OneNoteView, api::onenote and the OneNote part of --apps-test removed). Live on linuxlt: Recent / Pinned / My notebooks list as in Teams; opened OST Test Team Notebook's existing (untitled, 2026-11-06) page, typed "OST TEST 194 edit from OST": saved (cloud check), after a restart the notebook read "Just now" and the page still had the text; then removed it again (saved).

- 2026-11-20 merged as 2c746e0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneNote is hosted as Teams hosts it (its web app in the TeamsJS host); the native OneNote view and api::onenote were removed. Verified live: typed into an existing page in OST Test Team Notebook, restarted OST, text still there (shown Just now), then removed it.
<!-- SECTION:FINAL_SUMMARY:END -->
