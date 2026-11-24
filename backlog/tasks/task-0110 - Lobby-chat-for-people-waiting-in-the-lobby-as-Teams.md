---
id: TASK-0110
title: Lobby chat for people waiting in the lobby, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T16:50:00Z'
updated_date: '2026-11-11T17:36:00Z'
labels:
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
People waiting in a meeting's lobby get Teams' "Lobby chat" button on the waiting screen (after an unread lobby message) and read the organizers' messages, shown from "Meeting Organizer" with "Only organizers and people in the lobby can view these messages." OST receives the lobby thread (activeModalities.groupChat.lobbyThreadId) but doesn't show it while waiting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The waiting screen shows Teams' Lobby chat button once an organizer has written, measured on winpc
- [x] #2 It opens the lobby messages read-only as Teams shows them (Meeting Organizer, the info banner), verified with OST Test 2 waiting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11 (defdebf): measured Teams waiting in OST Test 2's scheduled meeting while OST (OST Test 2, organizer) wrote; built and verified with OST Test 2 waiting in OST Test 1's meeting.
- When the lobby thread already exists no conversationUpdate comes; the waiting client learns it from the thread's chat push (meetingChatType "lobby").
- Not built: the meeting title line Teams shows under the waiting greeting (not measured).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' lobby chat for people waiting in the lobby.

Changes:
- PreJoin: "Lobby chat" after Join now once an organizer has written; the Lobby pane (header, Teams' banner, read-only messages from "Meeting Organizer", listed from the top) opens with the first message; the pre-join content fits beside it.
- Backend: the lobby thread from the call's conversationUpdate or the lobby thread's chat push while waiting.
- Conversation: readOnly / noAvatars / hideHeader options.
- Lobby chat offered only for scheduled meetings (channel meetings answer 404); greeting by first name.

Tests:
- Live: Teams on winpc as the waiting reference; OST Test 2 waiting while OST Test 1 wrote, messages shown.
<!-- SECTION:FINAL_SUMMARY:END -->
