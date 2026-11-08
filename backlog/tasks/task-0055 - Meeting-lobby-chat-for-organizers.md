---
id: TASK-0055
title: Meeting lobby chat for organizers
status: To Do
assignee: []
created_date: '2026-11-08T02:16:00Z'
labels:
  - calls
  - meetings
dependencies: []
references:
  - desktop/qml/LobbyToast.qml
  - desktop/qml/PeoplePane.qml
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams lets a scheduled meeting's organizer chat with people waiting in the lobby: a chat button on the lobby toast and the People pane opens the meeting chat with a Lobby tab (lobbyThreadId). OST shows the lobby but not this chat yet, so the toast's chat button is left out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The lobby toast and People pane show Teams' lobby chat button for the organizer of a scheduled meeting with lobby chat enabled
- [ ] #2 The button opens the meeting chat pane on a Lobby tab bound to the call's lobby thread, and messages sent there reach people in the lobby
<!-- AC:END -->
