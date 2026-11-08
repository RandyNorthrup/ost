---
id: TASK-0055
title: Meeting lobby chat for organizers
status: To Do
assignee:
  - '@claude'
created_date: '2026-11-08T02:16:00Z'
updated_date: '2026-11-08T16:26:00Z'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-08 research:
  - Teams' lobby chat button (lobby toast, People) needs ECS enableLobbyChatForOrganizer, lobbyChatType "Enabled", you as organizer, one non-bot person waiting, and the call's lobbyThreadId.
  - The calling stack takes lobbyThreadId from the conversation's activeModalities.groupChat (join response or conversationUpdate). The UI reads it via subscribedCallChangedEvent.
  - OST advertises supportsLobbyChat (clientEndpointCapabilities 262144). Its join response has groupChat {threadId, messageId} and "lobby": null, and no conversationUpdate arrived with Guest 3 waiting. The thread properties have no lobby thread.
  - winpc's toast did show the chat button once (10:56, Guest 4 waiting), so the server gave winpc a lobby thread. Next: capture winpc's conversation traffic while someone waits (CDP Network, read-only) to see where it arrives.
- OST now parses lobbyThreadId (OutgoingCall::lobby_thread) for when it does arrive.

- Teams desktop's call signaling isn't visible to CDP (native calling stack): watching winpc's pages through a leave/rejoin showed no conversation traffic. Capturing winpc's lobby thread needs another route (Teams web as organizer, or the desktop's logs).
<!-- SECTION:NOTES:END -->
