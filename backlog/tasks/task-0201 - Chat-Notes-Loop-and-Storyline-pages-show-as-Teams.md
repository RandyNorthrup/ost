---
id: TASK-0201
title: Chat Notes (Loop) and Storyline pages show as Teams
status: Done
assignee: []
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-16T17:31:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0171 built the Notes and Storyline tabs around their pages: Notes finds or creates the chat's Loop page and draws Teams' header, loading, deleted and error pages; Storyline loads Teams' Viva Engage page for the right person. The pages themselves don't show yet: Teams loads Loop's page component in a frame fed its SharePoint tokens (the storage refuses the Loop web app), and Storyline needs a TeamsJS host (TASK-0053).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Storyline shows the person's Viva Engage storyline as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Storyline runs on OST's TeamsJS host (TASK-0053) and shows the storyline (checked with OST Test 2). Left: the chat Notes Loop page.

- The Loop page itself moved to TASK-0205 (needs Teams' Loop page container).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Storyline shows the person's Viva Engage storyline on OST's TeamsJS host (TASK-0053), as Teams. The chat Notes Loop page is TASK-0205.
<!-- SECTION:FINAL_SUMMARY:END -->
