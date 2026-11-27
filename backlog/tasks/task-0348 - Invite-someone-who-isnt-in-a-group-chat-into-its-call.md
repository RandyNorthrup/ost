---
id: TASK-0348
title: Invite someone who isn't in a group chat into its call
status: Done
assignee:
  - '@calls3'
created_date: '2026-11-27T07:35:00Z'
updated_date: '2026-11-27T13:10:00Z'
labels:
  - calls
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-0345. In a group chat's call, Teams' roster people picker also adds the invited person to the chat when they aren't a member (CallingAddParticipantService: conversationsAsyncService.addUsersToConversation before addParticipant). OST rings them into the call on the chat but doesn't add them to the chat; Teams' request for that wasn't captured (no test group chat without one of the test accounts was available).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inviting a non-member into a group chat's call from the People pane adds them to the chat as Teams does, verified between test accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams inviting a non-member into a group chat's call (Teams on the web as OST Test 3 over CDP, new chat with OST Test 1 + OST Test Room, invite OST Test 2) and read CallingAddParticipantService in Teams' bundles
2. Engine: add-to-chat rule + body (msgactions), invite_body meetingInfo for calls that have one
3. Desktop: start_invite adds the invitee to the call's chat alongside the ring
4. Live: OST (OST Test 1) group call in a chat without OST Test 2, invite OST Test 2; check membership, ring, answer
5. Spec, PR, CI + Codex
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Captured (Teams web as OST Test 3, Audio call in "OST TEST 348 invite" with OST Test 1 + OST Test Room, picker row > "Request to join" OST Test 2, 2026-11-27): POST .../add (202) and 60 ms later PUT chatsvc /v1/threads/{chat}/members {"members":[{"id":mri,"role":"Admin"}]} (200), in parallel. No shareHistoryTime is sent; the service set the member's shareHistoryTime to the time of the add (historydisclosed false), so no history. No dialog.
- Teams code (527114 handleAddParticipant): added only if not a member, not PSTN or bots, not a channel, not a meeting's chat (ECS addNudgedUserToThread false); fire-and-forget, chat-permissions alert on rejection.
- The /add in a group chat's call carries participantInvitationData.invitationData.meetingInfo {organizerId, tenantId} (extendParticipantPayloadToAddMeetingInfo, from the call's meetingInfo); 1:1 calls send {} (TASK-0345 capture). OST sent {} always.
- Implemented: msgactions::add_call_invitee_to_chat / adds_call_invitee / call_invitee_body; invite_body takes the call's meetingInfo (OutgoingCall: join/create answer; ActiveCall: attach answer, else the invitation's); backend start_invite adds the invitee to a group call's chat alongside the ring and reloads the call's chat members.

- Live 2026-11-27 on linuxlt (OST as OST Test 1, profile spatest, virtual mic ost_calls3_mic; Teams on the web as OST Test 3; Teams desktop on testpc2 as OST Test 2), chat "OST TEST 348 ost" (OST Test 1, OST Test 3, OST Test Room):
  - Teams web starts the chat's Audio call, OST answers and invites OST Test 2 from People: /add with meetingInfo, and the chat PUT at the same moment (member rangeStart 12:46:52.9, invite 12:46:52.1), shareHistoryTime = the add time as with Teams. testpc2's toast "OST Test 1 is calling you from a group" (Teams' own invite: "OST Test 3 is calling you from a group"); accepted, OST roster OST Test 3, OST Test 1, OST Test 2.
  - Teams web shows "OST Test 1 added OST Test 2 to the chat."; testpc2's chat list gained the chat.
  - A first run in which OST started the call right after launch: the chat service throttled the thread read (429 "20Per10Secs"), so the add failed once; the add is now retried as Teams' HTTP layer does (retry_throttled). The same throttle made OST's own group call ring nobody and become an adHocMeeting ("wants you to join a meeting"): separate bug, TASK-0350.
  - The mic streams (OST cpal, Chrome) recorded only from ost_calls3_mic.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Inviting someone who isn't in a group chat into that chat's call now adds them to the chat as Teams does, alongside the ring.

What Teams does (captured from Teams on the web, 2026-11-27, plus its bundles):
- In a group chat's call, picking a non-member in the People pane sends the call's `/add` and, at the same time (not before), `PUT {chatsvc}/v1/threads/{chat}/members` with `{"members": [{"id", "role": "Admin"}]}`. No `shareHistoryTime` is sent; the chat service shares the chat from the moment of the add. There's no history dialog.
- Only for non-members, and never in a channel or a meeting's own chat (ECS `addNudgedUserToThread` is off).
- The `/add` itself is unchanged, except that a call with a `meetingInfo` (a group chat's call, a meeting) carries `participantInvitationData.invitationData.meetingInfo {organizerId, tenantId}`. A 1:1 call sends `{}`.

Changes:
- `msgactions::add_call_invitee_to_chat`, `adds_call_invitee`, `call_invitee_body`: Teams' rule and body.
- `outgoing::invite_body` takes the call's meetingInfo (`meeting_organizer`). OutgoingCall gets it from its join or create answer; ActiveCall from the attach's answer, else the invitation's.
- backend `start_invite`: for a group call, adds the invitee to the call's chat alongside the invitation. It retries on 429, as Teams' HTTP layer does, and reloads the call's chat members.
- Spec: call-and-meeting-window.md, People pane.

Tests:
- Unit tests: `msgactions::add_members_tests::call_invitees_join_group_chats_as_teams_adds_them`, `outgoing::tests::invitations_are_teams` (group-call meetingInfo).
- Live: Teams on the web (OST Test 3) started the chat's call. OST (OST Test 1) answered and invited OST Test 2, who isn't a member.
  - OST Test 2 was added to the chat at the moment of the invite, with history from then on.
  - testpc2's toast read "OST Test 1 is calling you from a group", the same as for Teams' own invite.
  - OST Test 2 accepted and the roster showed 3.

Follow-up: TASK-0350. A group call OST starts while the chat's reads are throttled rings nobody and becomes an ad hoc meeting.
<!-- SECTION:FINAL_SUMMARY:END -->
