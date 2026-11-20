---
id: TASK-0230
title: 'Lobby: organizer sees people who joined before them'
status: To Do
assignee: []
created_date: '2026-11-20T02:13:00Z'
updated_date: '2026-11-20T03:27:00Z'
labels:
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0182's live runs: people who join a meeting before its organizer wait in the lobby, but the organizer's lobby list in OST stays empty, so they can never be admitted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When the organizer joins after people are waiting, OST's lobby list shows them and Admit works, as in Teams, verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 cause (linuxlt repro, OST calendar test, OST Test 2 + 3 waiting, ost-test1 organizer in OST): the join response roster already lists both waiting people (endpoints only in the lobby modality), and the first roster updates after Join now carry participantCounts.lobbyParticipants 2, but they arrive ~0.2 s before the preheated call is put into the call slot. refresh_lobby (the scope "lobby" getAllParticipants query, OST's only lobby source) found no call and returned silently; the count never changed afterwards, so callLobbyJson stayed [] and nobody could be admitted.
- Teams: its People pane partitions the call roster by participant state InLobby (calling-roster `partition(participants, isInLobby)`; remote state 7 when every endpoint isLobby), so people waiting before the organizer are in its lobby list at once; the scope-lobby query is only the XL drill-in. Seen live on winpc: Teams (ost-test1) joined with OST Test 2 + 3 (OST) waiting, showed "Waiting in the lobby" / View Lobby at once, "Waiting in lobby (2)", Admit all let both in (both OST logs: admitted, MCP session up), then left.
- Fix: roster Participant.in_lobby; roster::apply_lobby keeps who waits from every roster delta (join roster included); Backend.lobby_people + publish_lobby (shown only to non-attendees, Teams' rule, roster::sees_lobby); refresh_lobby waits up to 10 s for the call instead of dropping the refresh.
- Verified live: organizer in OST: "lobby from the roster waiting=2" at join, toast "OST Test 2 +1", both admitted (202), both OST attendees admitted; all three left (hung up 202).

- Also re-verified with the final build (v2 run): "lobby from the roster waiting=2" at join, both admitted, 1 then 0 as the roster moved them; everyone left. 798 lib tests pass.
- Open: the scope-lobby query that follows an Admit can still briefly return the people just admitted (seen before this change too); the next roster update corrects it.
<!-- SECTION:NOTES:END -->
