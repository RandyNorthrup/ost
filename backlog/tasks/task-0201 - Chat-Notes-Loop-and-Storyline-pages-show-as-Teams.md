---
id: TASK-0201
title: Chat Notes (Loop) and Storyline pages show as Teams
status: To Do
assignee: []
created_date: '2026-11-16T11:48:00Z'
updated_date: '2026-11-16T14:45:00Z'
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
- [ ] #1 A chat's Notes tab shows and edits its Loop page as Teams
- [x] #2 Storyline shows the person's Viva Engage storyline as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Storyline runs on OST's TeamsJS host (TASK-0053) and shows the storyline (checked with OST Test 2). Left: the chat Notes Loop page.
<!-- SECTION:NOTES:END -->
