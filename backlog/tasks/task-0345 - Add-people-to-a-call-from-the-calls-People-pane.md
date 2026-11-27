---
id: TASK-0345
title: Add people to a call from the call's People pane
status: In Progress
assignee:
  - '@calls2'
created_date: '2026-11-27T05:46:00Z'
updated_date: '2026-11-27T07:56:00Z'
labels:
  - calls
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in wiki round 3 (checklist row 215): Teams' call People pane lets you add people to an ongoing call (Invite someone / type a name or number); OST's People pane has no way to add people to a call.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The call's People pane has Teams' add-people box and adds a person to an ongoing 1:1 or group call as in Teams, verified between test accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams adding someone to a 1:1 call from its People pane (Teams on the web as OST Test 3 over CDP, OST Test 1 on testpc1, OST Test 2 on testpc2): the picker, the add request, the events, the escalation
2. Read Teams' code for how the escalated call's chat is chosen (CallEscalationService)
3. Engine: OutgoingCall/ActiveCall invite_people (Teams' add body on the addParticipantAndModality link), outcome parsing
4. Desktop: invite_to_call (1:1: group chat of everyone, existing or new; group call: its chat), pending "Calling..." people, escalation to the group-call window
5. QML: Teams' people picker in the People pane ("Invite someone or dial a number"), Calling... rows and tiles; --invite-test harness
6. Live: OST (OST Test 1) calls OST Test 3 (Teams web), invites OST Test 2 (Teams desktop, testpc2); compare with Teams
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop/web People pane in a 1:1 call: "Invite someone or dial a number" people picker (people-picker-search); suggestions = searchV2 people (name bold, address alias in capitals) and a number row for text that reads as a number.
- Picking a person in a 1:1 call: Teams finds the group chat with exactly the three people (getChatConversationWith, no request when it has one cached) and POSTs the conversation's addParticipantAndModality link (.../add) with {disableUnmute:false, participants:{from,to:[{id,participantId}]}, participantInvitationData:{}, replacementDetails:null, groupContext:null, groupChat:{threadId,messageId:null}, links:{addParticipantSuccess,addParticipantFailure}} -> 202; conversationUpdate isMultiParty true / conversationType groupCall, then mediaRenegotiation (moved to the MCU).
- The caller's window becomes a group call at once (Raise, React, View, Controls; gallery with a "Calling..." tile; roster "Currently in this call (3)" with "Calling..." on the right of the invitee). Invitee's Teams desktop toast: "OST Test 3 is calling you from a group". After a timeout the invitee moves to "People added to the chat (1)".
- The invitee isn't in rosterUpdate until they answer; "Calling..." is client state.

- Implemented: OutgoingCall/ActiveCall::invite_people (Teams' add body, outgoing::invite_body), invite_outcome; desktop invite_to_call (1:1: unnamed group chat with exactly the three people, hidden ones too, else a new one; group call: its chat), call_invites_json ("Calling..." rows and tiles), call_group (roster "Currently in this call", People added to the chat), escalation by the other side (incoming::escalated_to on conversationUpdate isMultiParty); PeoplePane people picker (1:1 box measured on testpc1: full-width #F0F0F0 33 tall at y 79; group: the search box); --invite-test harness.
- Live 2026-11-26/27 on linuxlt (OST as OST Test 1, Teams on the web as OST Test 3 and OST Test 2):
  - OST calls Test 3, invites Test 2 from People: 202, window turns into the group call at once (Raise/React/View/Controls), "Calling..." tile and row, Test 2 answers -> roster 3, both web clients see the 3-way call; decline (testpc2) -> "the person invited wasn't added", Test 2 moves to "People added to the chat (1)", as Teams.
  - Test 3 calls OST, OST answers and invites Test 2: works on the answered call (attach join's addParticipantAndModality), title "OST Test 2, OST Test 3".
  - Test 3 (Teams web) invites Test 2 into its 1:1 call with OST: OST turns the window into the group call ("the 1:1 call became a group call"), roster 3.
- Chat choice: with OST Test 1/2/3 in both "Release planning" (named) and an unnamed hidden chat, Teams took the unnamed one; OST now does too (first run had picked Release planning; a second run made one extra unnamed chat before the hidden-chat fix).
- Not done (follow-ups): the typed-number row and dialing out (TASK-0347, no test phone line), adding a non-member to a group chat when inviting them into its call (TASK-0348).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The call's People pane is now Teams' people picker ("Invite someone or dial a number"). Picking someone rings them into the ongoing call, as Teams does. PR #37.

Changes:
- Engine: `OutgoingCall::invite_people` / `ActiveCall::invite_people` send Teams' request: the addParticipantAndModality link with `outgoing::invite_body` (participantInvitationData {}, groupChat of the call's chat), captured from Teams on the web. `invite_outcome` reads addParticipantSuccess/Failure. `incoming::escalated_to` and `is_group_call` read conversationUpdate.
- Desktop:
  - `invite_to_call`: a 1:1 call goes on in the unnamed group chat with exactly those people (hidden ones too), else in a new one. A group call goes on in its own chat. The invitation goes only into the call it was asked for.
  - The window becomes the group call (`callGroup`, Teams' title from the chat's other members).
  - `callInvitesJson` shows "Calling..." until the person joins or fails.
  - A 1:1 call the other side escalates also becomes a group call, and a joined chat call with conversationType groupCall can invite.
- QML: the PeoplePane picker (1:1 box measured on Teams desktop: full width, #F0F0F0, 33 tall; 50 px suggestion rows, typed prefix in bold, alias in capitals). Also "Calling..." roster rows and tiles, "Currently in this call" for group calls, and the `--invite-test` harness.

Tests:
- Unit tests: `outgoing::tests::invitations_are_teams`, `incoming::tests::a_call_turning_multi_party_names_its_chat`.
- Live on linuxlt (OST as OST Test 1, Teams on the web as OST Test 3 and OST Test 2):
  - Outgoing 1:1 escalated: Test 2 joins and the roster shows 3.
  - Decline: Test 2 moves to "People added to the chat".
  - Answered 1:1 escalated by OST.
  - 1:1 escalated by the Teams side: OST turns into the group call.
  - The mic stream stayed on the virtual mic throughout.

Follow-ups:
- TASK-0347: dial a number (no test phone line).
- TASK-0348: add a non-member to a group chat when inviting them into its call.
<!-- SECTION:FINAL_SUMMARY:END -->
