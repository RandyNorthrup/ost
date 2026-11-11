---
id: TASK-0110
title: Lobby chat for people waiting in the lobby, as Teams
status: To Do
assignee: []
created_date: '2026-11-11T16:50:00Z'
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
- [ ] #1 The waiting screen shows Teams' Lobby chat button once an organizer has written, measured on winpc
- [ ] #2 It opens the lobby messages read-only as Teams shows them (Meeting Organizer, the info banner), verified with OST Test 2 waiting
<!-- AC:END -->
