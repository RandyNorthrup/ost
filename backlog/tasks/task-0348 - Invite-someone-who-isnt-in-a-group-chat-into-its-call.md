---
id: TASK-0348
title: Invite someone who isn't in a group chat into its call
status: To Do
assignee: []
created_date: '2026-11-27T07:35:00Z'
labels:
  - calls
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-0345. In a group chat's call, Teams' roster people picker also adds the invited person to the chat when they aren't a member (CallingAddParticipantService: conversationsAsyncService.addUsersToConversation before addParticipant). OST rings them into the call on the chat but doesn't add them to the chat; Teams' request for that wasn't captured (no test group chat without one of the test accounts was available).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Inviting a non-member into a group chat's call from the People pane adds them to the chat as Teams does, verified between test accounts
<!-- AC:END -->
