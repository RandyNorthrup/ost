---
id: TASK-0075
title: >-
  Chat list: remaining Teams items (Remove chat history, Open in new window,
  Notify when available, Manage apps, Set workflows; Followed threads and Saved
  quick views; Copilot row; team order)
status: To Do
assignee: []
created_date: '2026-11-09T12:32:00Z'
updated_date: '2026-11-09T12:42:00Z'
labels:
  - desktop
  - chatlist
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-0045. Teams' chat menu (measured on winpc 2026-11-09) also has:
- Open in new window;
- Notify when available (1:1);
- Manage apps and Set workflows;
- Remove chat history. Its enterprise call is DELETE {chatsvc}/v1/threads/{id}, which can't be tried here without a disposable chat that has other members.

Quick views also lists Followed threads and Saved (and Drafts from the server). The list starts with a Copilot row. Teams orders teams differently from the CSA list (Secure Coast before OST Test Team).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chat menu has Open in new window, Notify when available, Manage apps, Set workflows and Remove chat history as Teams (Remove chat history verified on a disposable chat)
- [ ] #2 Quick views show Followed threads and Saved with their views, and Drafts as Teams lists them
- [ ] #3 Teams are ordered as Teams orders them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- The chat header's ··· (More chat options) also lacks Open in new window (Ctrl+O), Share screen (Ctrl+Shift+E) and Remove chat history; they belong with this task.
<!-- SECTION:NOTES:END -->
