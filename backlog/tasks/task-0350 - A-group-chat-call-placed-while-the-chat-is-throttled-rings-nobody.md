---
id: TASK-0350
title: A group chat call placed while the chat is throttled rings nobody
status: Done
assignee:
  - '@calls4'
created_date: '2026-11-27T12:41:00Z'
updated_date: '2026-11-27T15:21:00Z'
labels:
  - calls
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0348's live checks (2026-11-27): when OST (OST Test 1) starts a group chat's Audio call right after launch, the chat service throttles the thread read (HTTP 429, 'API calls quota exceeded! 20Per10Secs'). outgoing::place_call then names no members ('Group members unavailable', 'group call members named members=0'), so nobody is rung and the service makes the call an adHocMeeting instead of a groupCall; an invitee then gets 'X wants you to join a meeting' instead of Teams' 'X is calling you from a group'. Teams uses its local copy of the chat's members.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Starting a group chat's call while the chat service throttles the thread still rings the chat's members and creates a groupCall, as Teams does, verified between test accounts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read how Teams names a group call's members (bundle module 300373: participants = chat.memberIds from its store) and how its HTTP layer handles 429 (HttpThrottleHandler, Retry-After).
2. api::client: typed HttpError carrying Retry-After; library retry_throttled honoring it (desktop uses it).
3. api::chat: keep each chat's members as last read (thread_member_ids); files::call_member_mris uses that copy, else reads with retry.
4. place_call: Ring/Huddle use call_member_mris and fail instead of starting a call that rings nobody; Join reads nothing.
5. Unit tests; spec note.
6. Live: throttle OST Test 1's thread reads with a burst, start the chat's call from OST on linuxlt, check groupCall + testpc2 (OST Test 2) toast "is calling you from a group".
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (bundle 26304, module 300373 getFireCallingIntentMutationVariables): a group chat's call is `GroupCall` with `coordinates.groupCall {conversationId: chat.id, participants: chat.memberIds || []}` from its store; nothing is read at call time.
- Teams' HTTP layer: HttpThrottleHandler reads `Retry-After` seconds on 429; its retry policy waits for a positive Retry-After, else backs off (1000*1.5^n).
- The chat service's thread throttle answers 429 "API calls quota exceeded! 20Per10SecswithDepth6" with Retry-After 0 (seen live), so a zero Retry-After counts as none.
- Rig: chat "OST TEST 350 call" (19:ff189e91fb8a4522aaa364e5960efc73@thread.v2; OST Test 1, 2, 3) made by OST Test 1; a burst of ~20 parallel thread GETs as OST Test 1 (examples/chat_get) throttles the thread.
- First live run (throttled the whole time, no copy of the members): the call read the chat, was throttled, and failed with "Couldn't start the call: Group members unavailable: HTTP 429" rather than start a meeting; it asked again immediately since Retry-After was 0, fixed to back off 2/4/8 s.

- Live 2026-11-27 on linuxlt (OST as OST Test 1, profile spatest, virtual mic ost_calls4_mic; testpc2 Teams desktop as OST Test 2), harness --group-call-nmc=<chat> --group-call-start right after launch:
  - Run A ("OST TEST 350 call", OST Test 1's thread reads kept throttled by bursts until the call read the members): known=false, 429, asked again after 2/7/4 s (one Retry-After 7), "group call members named members=2", the answer's conversationType "groupCall", group_call=true; testpc2's toast "OST Test 1 is calling you from a group".
  - Run B (same chat, only OST's own start-up throttle when the call was placed): the chat's reads at opening and at the call were refused (429) by OST's start-up burst alone; retried, members=2, groupCall, same toast.
  - Run C (new chat "OST TEST 350 copy" made 60 s after launch, opened and called by the harness): again throttled by OST's own reads when the chat appeared, retried, members=2, groupCall, same toast.
  - The copy path (members already read) couldn't be shown live because OST's own burst of meeting-thread reads throttles the chat-opening read too (follow-up TASK-0351); it is covered by api::files::tests::group_calls_name_the_chat_as_last_read.
  - OST's call audio recorded from ost_calls4_mic only (pactl source-outputs: ost-desktop on ost_calls4_mic; alsa_input SUSPENDED).

- Codex (PR #42): the kept members could go stale when another client changes a named chat's roster. Fixed in 05700159: each chat-list read records the chats' roster versions, and a changed version drops that chat's kept members (note_roster_versions).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A group chat's Audio call (and Meet now) now names the chat's members the way Teams does, so it rings them and is a groupCall even while the chat service throttles reads. Before, OST named nobody, and the call became an ad hoc meeting.

What Teams does (bundles 26304, module 300373):
- A group call's `participants` are the chat's `memberIds` from Teams' own store; nothing is read at call time.
- Its HTTP layer asks a throttled request again after a positive `Retry-After`, otherwise it backs off.
- The chat service's thread throttle sends `Retry-After: 0`.

Changes:
- `api::client`: `HttpError` (same text, carries `Retry-After`). `throttle_wait` and `retry_throttled` (waits for a positive Retry-After, else 2/4/8 s; three more tries). The desktop now uses this shared `retry_throttled`.
- `api::chat`: each chat's members as last read are kept (`known_member_ids`). They are dropped when the chat list gives that chat a new roster version (`note_roster_versions`).
- `api::files::call_member_mris`: names the kept members. It reads (with retries) only a chat not read yet.
- `outgoing::place_call`: Ring/Huddle fail with "Couldn't start the call: Group members unavailable" instead of a call that rings nobody. Join reads nothing.
- Spec: `chat-list-and-header.md`.

Tests:
- Unit tests: `api::client::tests` (3), `api::files::tests::group_calls_name_the_chat_as_last_read`.
- Live on linuxlt (OST Test 1) with testpc2's Teams (OST Test 2), calls placed right after launch while the thread reads were throttled (by bursts, and by OST's own start-up reads): 429, asked again, members=2, conversationType groupCall. testpc2's toast read "OST Test 1 is calling you from a group" in all three runs.
- CI, CodeQL and Codex are clean on PR #42.

Follow-up: TASK-0351. OST reads about 220 meeting threads on every chat-list read, which is what throttles it after launch.
<!-- SECTION:FINAL_SUMMARY:END -->
