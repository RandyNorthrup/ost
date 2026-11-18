---
id: TASK-0208
title: 'New meeting controls: drag and drop and remaining parts as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T21:56:00Z'
updated_date: '2026-11-18T23:54:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0155 left of Teams' New meeting controls (docs/spec/new-meeting-controls.md): dragging controls between the bar and More; Teams' dark and High contrast colours with the setting on (OST uses the Fluent tokens of its current bar); which controls show in Meet now and group calls compared with Teams (Teams showed Notes and Rooms in a Meet now); Teams Labs' revision reset of the choice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Controls can be dragged between the bar and More as in Teams
- [x] #2 Dark and High contrast with the setting on match Teams on winpc
- [x] #3 The controls shown in Meet now and group calls match Teams with the setting on and off
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (004a7a5, merged): drag and drop between the bar and More as Teams (2 px start, 0.7 copy, room made, More pressed and 0.4 copy, refused on Mic/Camera/Share/Leave, Escape cancels), saved like the right-click menu; dark and High contrast colours measured on winpc and applied with the setting on; channel Meet now treated as a meeting without Notes.
- Left on #3: group calls not measured live (every group chat of the test account includes real people); OST still hides Record, Captions, RTT and similar there, which Teams' rules show. Not built: touch hold, keyboard dragging, the 200 ms drop animation, screen-reader announcements.

- AC3 (2026-11-18): measured live on winpc — calendar Meet now (setting on and off, re-measured), a group chat's Meet now and its Audio call (test-only chat "OST TEST group call": ost-test1, OST Test 2, OST Test 3), setting on and off. Teams treats both chat calls as group calls: Record/Transcribe, Captions, RTT, Timer, Help and the accessibility settings show; Meeting info, Notes, Rooms, Facilitator and Report a concern don't. docs/spec/new-meeting-controls.md §8.
- OST: `ubar::Facts::group_call` shows those controls in group calls; Timer shows there (no presenter option); a ringing group call is joined as the chat's group call (`IncomingCall::group_thread`) instead of being answered as a 1:1 call, and its unanswered invitation's end no longer ends the call.
- Live with OST Test 2 (`--group-call-nmc`, `--group-call-answer`, `--group-call-huddle`): joining Teams' group Meet now and answering Teams' Audio call both give Teams' group-call bar and More, setting off and on. Left: Interpreter (OST has no AI interpretation); Call me depends on dial-in, which OST Test 2 lacks.

- 2026-11-18 (evening) recheck, OST Test 2 answering Teams' Audio call in "OST TEST group call": Teams' unanswered-invitation end (untagged call/end 408 "Call timed out without any signaling after attach from callee endpoints", ~58 s in) no longer ends OST's group call (CallSlot::group_invite_at); OST stayed connected until it left at ~2 min 45 s. The group call's dial-in from its join is now published, so Join info ▸ shows Call me and Call health, as Teams for an Audio Conferencing user.
- Interpreter / Call me requirements (Teams' code + live licence check): Interpreter needs ECS enableAiInterpretation and meetingPolicy.aiInterpreter "Enabled" (it is, for the test accounts) plus a Microsoft 365 Copilot licence (only ost-test1 has one; 24 trial seats unassigned), or the organizer turning interpretation on for everyone. Call me needs the call's isDialInEnabled + isPSTNEnabled and dial-in details for the meeting (organizer with Audio Conferencing: ost-test1 and OST Test 2 have it; OST Test 3 has not). docs/spec/new-meeting-controls.md §8.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' New meeting controls leftovers are done.

- Controls drag between the bar and More; dark and High contrast match Teams on winpc (earlier rounds).
- Meet now and group calls show Teams' set with the setting on and off (measured on winpc in a test-only group chat): Record/Transcribe, Captions, RTT, Timer, Help, accessibility settings; no Meeting info, Notes, Rooms, Facilitator or Report a concern. A ringing group call is joined as the chat's group call; an answered group call stays up (the unanswered invitation's id-less end is ignored); Join info shows Call me and Call health for Audio Conferencing users.
- Verified live as OST Test 2 against Teams' group Meet now and Audio call, setting off and on.
- Interpreter needs a Copilot licence and AI interpretation: follow-up TASK-0225.
- Tests: 748 lib, 29 desktop crate tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
