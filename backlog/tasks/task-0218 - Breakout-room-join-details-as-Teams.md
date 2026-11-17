---
id: TASK-0218
title: Breakout room join details as Teams
status: Done
assignee: []
created_date: '2026-11-17T06:54:00Z'
updated_date: '2026-11-17T20:43:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0216 left (docs/spec/call-and-meeting-window.md §1.8l): OST doesn't send meetingData {meetingCode, passcode} with a room's call (its source wasn't captured); while in a room Teams leaves the main conversation and at once rejoins it without a call (to keep the main meeting's updates), OST rejoins the main meeting in two steps instead; a failed room join shows an alert, not Teams' full retry screen in the room's window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Room calls carry meetingData and OST keeps the main conversation while in a room, as Teams
- [x] #2 A failed room join shows Teams' retry screen in the room's window
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Source of meetingData found in the TASK-0216 capture (Trouter bodies decoded): the conversation-only join's conversation/conversationUpdate carries top-level meetingData {meetingCode, passcode}; Teams keeps it (calling-shell: e.meetingData && (this.meetingData = e.meetingData)) and sends it with the call. OST now waits up to 2 s after the conversation join on a move (or an organizer's Join over the held main meeting) for that tagged update and sends it with the call (signaling::meeting_data_of / await_meeting_data).
- Keeping the main meeting: once the room answers, a participant leaves the main meeting (POST links.leave) and joins its conversation again without a call at the conversation's URL (signaling::join_conversation_without_call, new participant id and tag; outgoing::KeptConversation keeps its meetingData from its updates). Going back posts the call straight to it (groupChat null, its meetingData, the kept participant id), then the room is left. Left on Leave, or 30 s after a call ends with nothing going back.
- Retry screen: Teams' NotAllowedToJoinBreakoutRoom (403 / 5745) has no icon, the title and description, and no retry button (isRejoinable false via checkBreakoutRoomsConditions) - Dismiss only - in the room's window. OST: RetryScreen reason notAllowedToJoinBreakoutRoom in the call window; the meeting we came from stays on hold in its own window with Resume (organizer's held main meeting; a participant's main meeting too, its breakout state restored on Resume). The refusing room's own "closed" state no longer starts the move-back countdown. The held window shows even while the call window is hidden.
- Found while testing: Join now while the pre-join's preheat was still being placed dropped the preheat request mid-flight, leaving a preheated endpoint in the meeting (preheatedParticipants 1); the watcher now lets it finish (withdrawn, a late answer left). With that ghost gone the organizer stays alone in the main meeting fine.
- Live on linuxlt (OST Test 2 organizing in OST, ost-test1 participant in OST, meeting3): the participant's Room 1 call and the organizer's room calls carried meetingData; the participant kept the main conversation and returned through it (call posted to it with the main meeting's meetingData, joined in ~1.4 s, room left); the organizer's Join on unopened Room 2 showed the retry screen with the main meeting held ("On hold", Resume), then Dismiss + Resume brought it back; rooms removed, both left. Screens: bro4-rooms-unopened-join.png, bro4-rooms-unopened-held.png, brp4-watch-*.png on linuxlt /tmp/j219.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Room calls and a refused room work as in Teams.

Changes:
- Room calls carry meetingData from the update after the conversation join.
- In a room, the participant leaves the main meeting and rejoins its conversation without a call. Going back posts the call straight into it.
- A refused room (403/5745) shows Teams' screen in the room's window (title and description, Dismiss); the main meeting stays held with Resume.
- Harness --breakout-watch-join; the organizer test removes stale rooms. Spec §1.8l.

Tests:
- Live, with OST Test 2 organizing and ost-test1 as participant, both in OST:
  - every room call had meetingData;
  - going back took about 1.4 s;
  - the organizer joining an unopened room got the retry screen, then Dismiss and Resume.

Follow-up: TASK-0222 (late joiners, a refused participant).
<!-- SECTION:FINAL_SUMMARY:END -->
