---
id: TASK-0175
title: New chat form as Teams (note before picking, compose always shown)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T14:52:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' new-chat form shows a note before anyone is picked and always shows the compose box; OST's form is its own.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The new chat form matches Teams' layout and text before and after picking people
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (7d40c0a, merged), measured in Teams on the web (read-only); spec docs/spec/chat-list-and-header.md §7.3.
- New message row, To: row with Teams' placeholder, chips, group-name chevron, the "You're starting a new conversation" note, an existing 1:1's history under the To: row. Re-checked on the merged build (--new-chat-form-test).
- Suggestions and compose gaps found on winpc: TASK-0204.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The new chat form as Teams: the "New message" row in Chats, the To: row (placeholder, person chips, group name), suggestions before typing, the new-conversation note, and an existing chat's messages when you pick someone you already chat with (sending from it closes the form). Harness --new-chat-form-test. Follow-up TASK-0204 (suggestion rows, compose in a new conversation).
<!-- SECTION:FINAL_SUMMARY:END -->
