---
id: TASK-0325
title: Lobby chat messages don't reach people waiting
status: Done
assignee:
  - '@meet'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T16:10:00Z'
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
- [x] #1 Lobby chat works both ways between organizer and people waiting, as in Teams, verified live with test accounts
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Lobby chat now works both ways between organizers and people waiting.

Cause: Teams' organizer to OST waiting already worked, for a new lobby thread and for an existing one. OST as the organizer lost its own meeting role a moment after joining. Teams sends the organizer's roster entry with advancedMeetingRole, then an update with only {details: {displayName}, state}. roster::apply replaced the whole entry, so lobbyChatAvailable went false, hiding the lobby toast's chat button and the Lobby tab.

Changes:
- roster::apply keeps a participant's meeting role until an update carries one, as Teams' participant model merges updates.
- Spec (call-and-meeting-window.md, lobby chat) records how each side learns the lobby thread.

Tests:
- Unit: an_update_that_only_names_someone_keeps_their_role.
- Live 2026-11-26 in "OST TEST 324 meet", lobby "Only organizers and co-organizers":
  - Teams on the web (ost-test1) as organizer to OST Test 3 waiting: both messages arrived, for a new thread and for an existing one.
  - OST (ost-test1) as organizer: role organizer, toast chat and Lobby tab shown. Its message reached OST Test 3 waiting in OST, and Teams on the web (OST Test 2) waiting.
  - People waiting can't reply, as in Teams.

PR #16.
<!-- SECTION:FINAL_SUMMARY:END -->
