---
id: TASK-0222
title: >-
  Breakout and preheat leftovers as Teams: late joiners' rooms, refused
  participant, ongoing-meeting preheat
status: Done
assignee: []
created_date: '2026-11-17T20:43:00Z'
updated_date: '2026-11-18T10:55:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0218/0219 left: a participant who joins after rooms are open isn't offered their room; a participant refused by a room was never observed in Teams (OST keeps the main meeting on hold with Resume); Teams' joinOngoingMeetingInPreheatedFlow (on for ost-test1) isn't understood or done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A participant who joins after breakout rooms are open is moved to or offered their room as Teams does, verified live
- [x] #2 A participant refused by a room sees what Teams shows, observed in Teams and matched
- [x] #3 What joinOngoingMeetingInPreheatedFlow changes in Teams is found and OST does the same, verified against Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop watched on winpc (MSTeams 26304.1201, live bundle 648378-56a5a3527cf9ed7b.js) with CDP logpoints in its calling code; DOM read as text, no stage screenshots. Live ECS: enableMoveWithinSameWindow, enableRetryMoveOnTargetCallDisconnect and joinOngoingMeetingInPreheatedFlow all true; enableWaitForTargetCallRemovalBeforeMoveRetry false.
- AC1, Teams: a late joiner assigned to an open room already has it when the main call connects (Room 1 open). Teams takes that room as its starting point (resetPrevAssignedRoom), so the change type is null: no move, no alert, no dialog. Join room sits on the bar (Calling controls, before Leave), and pressing it moves the participant in (GoToAssignedBreakoutRoom, same window, main meeting left once the room connects). A room assigned or opened after joining moves you (breakoutRoomInviteFromMainMeeting).
- AC1, OST: Main.qml ports Teams' change rule (breakoutChange; starting point = assigned room when connected). Join responses carry breakoutDetails (breakout::assigned_rooms_at_join, JoinedView.breakout). Rooms assigned while preheated are no longer dropped: Preheat.breakout keeps them for Join now. Before this fix a late joiner on the pre-join path got no room at all.
- AC2, Teams: Teams' own move (moveToNewMeeting) into an unopened room ended 403/5745. Teams retried once (retryMoveAfterTargetDisconnect), then showed nothing: the participant stayed connected in the main meeting, same window, never on hold. No retry screen, alert or toast.
- AC2, OST: a participant's failed move is tried once more, then OST stays in the main meeting silently. The held main window and retry screen are now only for an organizer's Join. A refusing room's closed state no longer starts the move-back countdown while still connecting.
- AC3, Teams: with the flag on, startPreheating asks getExistingCallInfo. If the meeting's call is going on, it calls joinExistingCall, i.e. call.join({conversationUrl, conversationId}) from the chat's awareness_conversationLiveState; otherwise call.start. On winpc the flag-on branch ran (logged), but ost-test1's active calls had no entry for meeting3 (it had left that chat), so Teams started the call there. SlimCore's wire is not visible. Teams web (flag off) captured in OST's web profile: conversation join first, then the call.
- AC3, OST: preheat_joins_ongoing reads the ECS flag. An ongoing meeting's preheat posts the call straight to the liveness conversationUrl, with groupChat null and the liveness meetingData; LiveCall.meeting_data was added. Live run ph1 (ost-test1 preheating meeting3 with OST Test 2 in it): preheating its call where it is, 200 OK, Phone audio from details, Join now, roster [OST Test 1, OST Test 2], left.
- Live OST runs on linuxlt in /tmp/brk: late3 (late joiner: assigned when connected Room 1 open, no alert, Join room on bar; late3-watch-3.png), late2 (direct join, same), try2 (refused participant: retried, stayed, nothing shown; try2-watch-*.png). Lib tests: 724 passed.

- Merged 8eca4e7 (2026-11-18): build OK, 724 lib tests passed. AC1 and AC2 verified live against Teams. AC3 open: Teams' direct join of an ongoing call is traced in its bundle and seen at a logpoint, but not yet watched end to end on winpc.

- 2026-11-18 lobby on return (winpc, meeting3 lobby OrganizerOnly): Teams' Leave room put the main meeting's new call InLobby while the room's call stayed Connected and its window kept showing Room 1, with no lobby screen; once admitted, the main call connected and the room was left. OST now matches (CallSlot::lobby_return: stay in the room until let in, then leave it). Verified live in run lr1: held in the lobby, stayed in Room 1, let in 1.6 s later, room left, back in the main meeting.
- 2026-11-18 AC3 re-check: OST Test 2 re-added ost-test1 to meeting3's chat, and OST Test 3 held a call in meeting1. Teams desktop's active calls still had only expired entries for both chats, so the preheat found no running call (flag-on branch, existing false); meeting1's pre-join wasn't preheated at all. Teams' join-the-running-call branch was not observed end to end.

- Merged ed02e5d (2026-11-18): returning from a room to a main meeting with a lobby stays in the room until admitted, as Teams does (verified live, run lr1). Build OK, 724 lib tests passed. AC3 is still being observed on winpc; the "Join breakout room?" dialog is being built.
- 2026-11-18 AC3 seen end to end in Teams desktop: after restarting new Teams (CDP on 9222 again), its pre-join for meeting3 (OST Test 2 in the call, ost-test1 a chat member again) logged existing true, then joinExistingCall with callUrl = the running call's conversation (conv/zkU0y2ykEUSykw..., the same URL in OST Test 2's log) and callId = the live state's conversationId. A running Teams doesn't refresh a chat's live state after a re-add; the restart reloads it. OST posts its preheat to the same URL with that id as chain id, so no change was needed.
- 2026-11-18 Join breakout room? invite: measured in Teams desktop (calling alert ufd_BreakoutRoomInvite; geometry, fonts and colours in spec 1.8l). It stays until answered; Later closes it and Join room stays on the bar. OST: BreakoutInviteAlert.qml replaces the old assigned-to alert. Verified live (ost-test1 organizing meeting1 in OST, OST Test 3 participant): the invite showed (linuxlt:/tmp/brk/inv1-watch-4.png), and its Join room moved OST Test 3 into Room 1.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Breakout and preheat leftovers now behave as Teams.

- Late joiners: the room assigned when the call connects is the starting point (kept from the join and the preheated call); only later changes move you. "Join room" sits on the bar, no alert (verified live, runs late2/late3).
- Refused participant: a participant's move is retried once, then OST stays in the main meeting silently; the retry screen and hold stay only for an organizer's Join from a room's menu. Fixed a wrong "We'll move you back" alert (run try2).
- Ongoing-meeting preheat (joinOngoingMeetingInPreheatedFlow): the preheated call is posted straight to the running call's conversation with its id, as Teams does; seen end to end in Teams desktop and matched (run ph1).
- Return to a main meeting with a lobby: OST stays in the room until admitted, then leaves it (run lr1).
- "Join breakout room?" invite (BreakoutInviteAlert.qml) as Teams draws it, with Later and Join room (run inv1).
- Harness: --breakout-late, --breakout-unopened-wait, --breakout-watch-try, --breakout-watch-invite. Spec 1.8k/1.8l.
- Tests: 724 lib tests pass. Follow-up TASK-0224 (main audio during a move) is done.
<!-- SECTION:FINAL_SUMMARY:END -->
