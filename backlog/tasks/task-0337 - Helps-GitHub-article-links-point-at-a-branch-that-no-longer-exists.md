---
id: TASK-0337
title: Help's GitHub article links point at a branch that no longer exists
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T15:21:00Z'
updated_date: '2026-11-26T18:12:00Z'
labels:
  - bug
  - help
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
src/feedback.rs docs_url() defaults to the desktop/foundation branch, which was removed when the fork moved to a single main branch (2026-11-24), so Help's links to an article or to all articles on GitHub open a 404 page. Found while working on TASK-0336.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help's links to its articles on GitHub open the articles on the main branch
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help's links to its articles on GitHub (src/feedback.rs docs_url) defaulted to the desktop/foundation branch, removed on 2026-11-24, so they opened a 404. They now default to main (a build can still set OST_DOCS_BRANCH).
<!-- SECTION:FINAL_SUMMARY:END -->
