---
id: TASK-0075
title: >-
  Chat list: remaining Teams items (Remove chat history, Open in new window,
  Notify when available, Manage apps, Set workflows; Followed threads and Saved
  quick views; Copilot row; team order)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T12:32:00Z'
updated_date: '2026-11-10T06:17:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' chat menus (group, 1:1, meeting) and each new item.
2. Chat pop-out (ChatWindow over Conversation popout mode), Manage apps (TeamAppsView chat mode), Set workflows (chatworkflows), Notify when available (contactsv3), Remove chat history.
3. Quick views Followed threads / Saved; team order.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- The chat header's ··· (More chat options) also lacks Open in new window (Ctrl+O), Share screen (Ctrl+Shift+E) and Remove chat history; they belong with this task.

- Also from the old TASK-0046 list: the meeting chat's "+4" tabs (Attendance, Breakout Rooms, Q&A, Meeting Whiteboard) and Add a tab; Report a concern in a meeting chat's ··· (tenant policy reportMeeting); Add agents.

- Chat menu: Open in new window (ChatWindow, sends to its chat), Notify when available / Turn off notifications (contactsv3 Tagged, captured on and turned back off), Manage apps (chat's Installed apps), Set workflows (chatworkflows URL captured), Remove chat history (question measured; request not tried). Report a concern on meeting chats still to do.
<!-- SECTION:NOTES:END -->
