---
id: TASK-0170
title: >-
  Suggested replies: file, meeting and workflow suggestions and feedback, as
  Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T11:49:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' suggested replies also suggest sharing a file, a meeting or a workflow and have a feedback button. OST parses those kinds but shows only text chips.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 File, meeting and workflow suggestions show and act as Teams'
- [x] #2 The feedback button works as Teams' (no data sent to Microsoft)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (da0a317).
- File suggestions verified on real data: OST TEST 170a from Teams to OST Test 2 got Cortana's file suggestion; OST (as OST Test 2) showed Share a file and the lightbulb, and Share a file opens the attach menu.
- Meeting and workflow suggestions are off in this tenant (Teams shows none either); OST draws them from Teams' rules (checked with --smart-reply-fake). The workflow dialog is TASK-0202.
- Feedback goes to OST's GitHub issue form, never to Microsoft.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Suggested replies as Teams: file, meeting and workflow suggestions and the feedback button.

- Share a file opens the attach menu; the meeting chip opens the new-meeting form with the chat's members and time; the workflow chip (when the tenant enables it) opens Workflows.
- Teams' rules: file suggestions only in 1:1 chats on one of the newest three messages; tenant defaults from ECS.
- SmartReplyFeedback.qml: Teams' form; Send opens OST's GitHub issue (your message included only if ticked).

Tests: issue link unit test; live file suggestion with OST Test 2. Follow-up: TASK-0202.
<!-- SECTION:FINAL_SUMMARY:END -->
