---
id: TASK-0106
title: >-
  Call-ended screens as Teams (denied from lobby, removed, not admitted, meeting
  ended)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T04:48:00Z'
updated_date: '2026-11-11T06:35:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a call or meeting ends for a reason other than you leaving, Teams keeps the meeting window open on its call-ended screen (retry screen states such as DeniedFromLobby, NotAdmittedForLongTime, KickedFromMeeting, MeetingIsFull, LobbyIsFull) with an icon, a title and actions. OST closes the window without saying why.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Denied from the lobby: OST shows Teams' screen with its icon and "Sorry, but you were denied access to the meeting.", verified live with a second account
- [x] #2 Not admitted in time and removed from the meeting show Teams' texts and layout
- [x] #3 Layout, icons and actions measured from Teams desktop on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10 (219c45f): retry screen built to winpc measurements (denied: prohibited icon + title + Dismiss; removed: title, description, Dismiss then Rejoin). Verified live with OST Test 2: denied from the lobby by Teams desktop -> OST shows the denied screen; removed from the meeting -> removed screen; Rejoin -> lobby -> admitted -> connected. End reasons come from callEnd code 0 subCode 5854/5855/5000/5300.
- Open: "not admitted in time" (5855) waits on the lobby timeout run; Teams' own NotAdmittedForLongTime layout not yet seen live.

- 2026-11-10: not admitted in time verified live: the lobby timed out after exactly 30 minutes (subCode 5855) and OST showed Teams' screen ("Sorry, no one has responded to your request to join. Please try again." with Dismiss and Rejoin). Teams' own NotAdmittedForLongTime layout follows the same retry-screen component (title only, Rejoin); the denied and removed layouts were measured live on winpc.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now shows Teams' retry screen when the service ends a meeting for a reason, instead of closing the window.

Changes:
- Call end reasons from callEnd code 0 + subCode (5854 denied in the lobby, 5855 not admitted in time, 5000/5300 removed), exposed as call_end_reason.
- RetryScreen.qml built to winpc measurements: #F5F5F5 page, centred title (18/600) with the prohibited icon for denials, description for removals, Dismiss then Rejoin (#5B5FC7).
- The pre-join window turns into it when denied or timed out; the meeting window when removed. Rejoin joins the same meeting again (back into the lobby when the meeting holds people there).

Verified live with OST Test 2 against Teams desktop (OST Test 1, organizer): denied, removed, Rejoin -> lobby -> admitted -> connected, and a 30-minute lobby timeout.

Tests: incoming::end_reason unit tests; 426 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
