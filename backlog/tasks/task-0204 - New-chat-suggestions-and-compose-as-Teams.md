---
id: TASK-0204
title: New chat suggestions and compose as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T14:52:00Z'
updated_date: '2026-11-16T20:22:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0175 built Teams' new chat form. Measured on winpc 2026-11-16, Teams' suggestions before typing differ from OST's:
- Teams lists people only: no bots (OST lists Workflows) and no duplicate of your own chat (OST lists "OST Test 1" and "OST Test 1 (You)").
- Each row has a second line, 12 px #616161: the person's alias in capitals (OST-TEST2, RANDY); guests show "Guest" and their email (OST Guest 01…09).
- Teams then lists the OST guests after recent people.
Also in a new conversation OST's compose Attach and Actions do nothing and messages go as plain text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The new chat form's suggestions list the same people, order and second lines as Teams on winpc
- [x] #2 Compose in a new conversation attaches, runs actions and sends formatted text as in an existing chat
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (dd601ea). Teams' people-suggestion request, top 20, people only, you once; second line = sign-in name before @ in capitals ("(ALIAS) job" with a title); guests with the Guest tag and email. OST's list matched Teams row for row on winpc.
- New-conversation compose: files, "+" list, video clips, formatted text with files (formatting and importance kept; OST TEST 0204 compose 4 checked in Teams).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New chat suggestions and compose as Teams: same people, order and second lines as Teams on winpc; attaching, actions and formatted text work in a new conversation.
<!-- SECTION:FINAL_SUMMARY:END -->
