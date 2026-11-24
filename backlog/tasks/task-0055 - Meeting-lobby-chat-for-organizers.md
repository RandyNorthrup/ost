---
id: TASK-0055
title: Meeting lobby chat for organizers
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T02:16:00Z'
updated_date: '2026-11-11T16:50:00Z'
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
- [x] #1 The lobby toast and People pane show Teams' lobby chat button for the organizer of a scheduled meeting with lobby chat enabled
- [x] #2 The button opens the meeting chat pane on a Lobby tab bound to the call's lobby thread, and messages sent there reach people in the lobby
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

- 2026-11-11 live test: OST Test 2 (OST, advertises supportsLobbyChat) waited in the lobby of OST Test 1's meeting while Teams desktop (winpc) and OST (linuxlt) were both in it as OST Test 1. Teams' toast showed the lobby chat button (so a lobby thread existed); OST got the rosterUpdate (lobbyParticipants 1) and the lobby list, but no conversationUpdate at all, though its join registers the conversationUpdate callback. Next: find how Teams desktop gets lobbyThreadId (its calling stack may fetch it, or receive it on a channel OST does not subscribe to).

- 2026-11-11 (2978983): built and verified live. The lobby thread comes from POST {mt}/beta/meetings/lobby/getOrCreateLobbyChatThreadId (captured from Teams desktop when it sent its first lobby message); people waiting get it as activeModalities.groupChat.lobbyThreadId. OST's toast chat button and People pane "Chat" open the Lobby tab; the message OST sent ("OST test 97…") was readable by OST Test 2 while it waited.
- Naming: Teams names masked lobby members ("Attendee (OST Test 2)") through the call participant's maskedIdSeqNumber; OST names them only while exactly one person waits.
- Fixed on the way: people waiting in the lobby showed as stage tiles (roster entries with lobby-only endpoints are now not in the meeting).
- Test messages: OST test 96 (from Teams) and OST test 97 (twice, from OST) in the meeting's lobby thread.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' lobby chat for meeting organizers.

Changes:
- api::meeting_options::lobby_chat_thread (getOrCreateLobbyChatThreadId); backend call_lobby_thread + open_lobby_chat; the thread stays live through the chat-window path.
- Lobby toast chat button and People pane lobby "Chat" (organizers, one person waiting), measured on winpc.
- Call chat pane tabs Everyone | Lobby with Teams' waiting badge; the Lobby tab shows the empty chat header, "is in the lobby" rows and messages; Teams' compose note, the disabled state with nobody waiting, Format and Send only.
- Messages: ThreadActivity/MemberJoined with temporary members reads "… is in the lobby."
- Roster: lobby-only participants aren't in the meeting (no stage tile).

Tests:
- 432 lib tests (lobby event text, lobby-only roster entries).
- Live with OST Test 2 waiting and Teams desktop on winpc; message delivery confirmed from OST Test 2's side.
<!-- SECTION:FINAL_SUMMARY:END -->
