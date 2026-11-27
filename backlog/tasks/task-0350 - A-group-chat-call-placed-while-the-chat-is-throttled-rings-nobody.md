---
id: TASK-0350
title: A group chat call placed while the chat is throttled rings nobody
status: To Do
assignee: []
created_date: '2026-11-27T12:41:00Z'
labels:
  - calls
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0348's live checks (2026-11-27): when OST (OST Test 1) starts a group chat's Audio call right after launch, the chat service throttles the thread read (HTTP 429, 'API calls quota exceeded! 20Per10Secs'). outgoing::place_call then names no members ('Group members unavailable', 'group call members named members=0'), so nobody is rung and the service makes the call an adHocMeeting instead of a groupCall; an invitee then gets 'X wants you to join a meeting' instead of Teams' 'X is calling you from a group'. Teams uses its local copy of the chat's members.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Starting a group chat's call while the chat service throttles the thread still rings the chat's members and creates a groupCall, as Teams does, verified between test accounts
<!-- AC:END -->
