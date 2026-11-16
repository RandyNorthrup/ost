---
id: TASK-0195
title: Live checks of built-but-untried actions with the test accounts
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T20:22:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Built but never run live: creating and joining teams, adding team members and deleting teams, deleting custom emoji, Leave chat and Remove chat history, the Communities search result card. The test tenant now allows all of them (2026-11-15).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each runs live with test teams, chats and emoji and matches Teams on winpc; anything that differs is fixed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Run live by a subagent (dd601ea) against Teams on winpc: create team (Teams' newer request, Add members step), join (OST Test 2), add members (fixed: guests get the guest role), delete team (fixed: OST drops it at once), delete custom emoji (dialog resized to Teams'), Leave chat with Remove chat history (Teams' dialog, the non-member compose text, menu), Communities search card (redone to Teams' single row).
- Test teams, chats, emoji and section created and removed; leftovers found: TASK-0206.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Team, emoji and chat actions run live and match Teams on winpc; guest adds, team deletion, the emoji dialog, Leave chat and the Communities card were fixed along the way. Follow-up TASK-0206.
<!-- SECTION:FINAL_SUMMARY:END -->
