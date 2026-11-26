---
id: TASK-0325
title: Lobby chat messages don't reach people waiting
status: In Progress
assignee:
  - '@meet'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T14:50:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). A lobby chat message sent from the meeting never reached the person waiting in the lobby.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lobby chat works both ways between organizer and people waiting, as in Teams, verified live with test accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce with Teams on the web (ost-test1, organizer) and OST waiting, and with OST as the organizer
2. Compare the lobby chat hand-off and fix what OST misses
3. Verify both directions live
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-26 rig: "OST TEST 324 meet" (organizer ost-test1, Graph event from Teams on the web), lobby "Only organizers and co-organizers"; Teams on the web in Chrome on linuxlt as ost-test1 and as OST Test 2; OST Test 3 / ost-test1 OST on linuxlt.
- Teams organizer to OST waiting already worked: a new lobby thread arrives in a conversationUpdate (activeModalities.groupChat.lobbyThreadId), an existing one in the chat push (ConversationUpdate addedBy, then NewMessage); OST shows only messages sent while waiting, as Teams.
- Cause of the wiki failure: OST as organizer. Teams sends the organizer's roster entry with advancedMeetingRole, then one with only {details: {displayName}, state}; roster::apply replaced the entry and the role went empty, so lobbyChatAvailable was false (toast chat button and Lobby tab hidden).
- Fix: roster::apply keeps a participant's role when an update carries none (unit test an_update_that_only_names_someone_keeps_their_role).
- Verified: OST organizer (role organizer, toast chat shown, Lobby tab shown) sent "OST test 97: lobby chat from OST": OST Test 3 waiting in OST got it; Teams on the web (OST Test 2) waiting showed it under "Meeting Organizer" with its Lobby chat pane. Teams organizer to OST Test 3 waiting: both messages shown in OST's Lobby pane (new thread and existing thread). People waiting can't reply in Teams ("They can view messages but not reply").
<!-- SECTION:NOTES:END -->
