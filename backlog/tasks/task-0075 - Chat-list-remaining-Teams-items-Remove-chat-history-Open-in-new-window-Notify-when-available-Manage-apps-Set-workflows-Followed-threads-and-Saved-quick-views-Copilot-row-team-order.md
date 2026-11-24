---
id: TASK-0075
title: >-
  Chat list: remaining Teams items (Remove chat history, Open in new window,
  Notify when available, Manage apps, Set workflows; Followed threads and Saved
  quick views; Copilot row; team order)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T12:32:00Z'
updated_date: '2026-11-11T22:21:00Z'
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
- [x] #1 Chat menu has Open in new window, Notify when available, Manage apps, Set workflows and Remove chat history as Teams (Remove chat history verified on a disposable chat)
- [x] #2 Quick views show Followed threads and Saved with their views, and Drafts as Teams lists them
- [x] #3 Teams are ordered as Teams orders them
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

- Quick views: Followed threads (48:threads) and Saved (48:saved) as Teams lays them out, compared on winpc; team order from the teamsOrder preference then the service order (Secure Coast before OST Test Team, as Teams).
- Left for AC #1: Remove chat history can't be verified without a disposable chat with other members; meeting chats' Report a concern item.

- Meeting chats' Report a concern done (a763659): Hide | Report a concern, the meeting's "Report a security concern" filled from the chat (subject, Nov 6, 3:00 PM, OST Test 1), members to name; dialog checked, never sent.

- Chat header More chat options as Teams (33e553f): group/1:1, meeting and own-chat lists match winpc item for item; Ctrl+O and Ctrl+Shift+E. Share screen (call + share on connect) not tried live: it would ring a real member.

- Copilot row moved to TASK-0038 (Teams hosts Copilot as an embedded web app, which needs that task's web-app host). Left here: Remove chat history verified on a disposable chat (needs the user: every chat with other members is a real one).

- Remove chat history (2026-11-11): Teams sets PUT {chatsvc}/v1/users/ME/conversations/{id}/properties?name=clearHistoryTime {"clearHistoryTime": now ms}, not DELETE v1/threads (OST's old call). OST now does the same: hides the chat (listed again when something newer arrives), moves off it if open, and filters messages up to clearHistoryTime. Verified on a disposable 1:1 between OST Test 1 and OST Test 2 (Teams removed it on OST Test 1, OST removed it on OST Test 2; after a new message only that message shows in both).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The chat list's remaining Teams items are in place.

- Chat menu (list and header): Open in new window, Notify when available (1:1), Manage apps, Set workflows, Copy link, and Remove chat history; meeting chats have Report a concern in its place.
- Remove chat history now does what Teams does: sets the chat's clearHistoryTime (it used to try to delete the thread), hides the chat until something newer arrives, moves off it when open, and shows only newer messages. Verified on a disposable 1:1 between the two test accounts, both from Teams and from OST.
- Quick views: Followed threads and Saved with their views; Drafts as Teams lists them.
- Teams ordered as Teams orders them.
- The Copilot row moved to TASK-0038 (an embedded web app).

Tests: 447 unit tests; live checks on winpc and linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
