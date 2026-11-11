---
id: TASK-0106
title: >-
  Call-ended screens as Teams (denied from lobby, removed, not admitted, meeting
  ended)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-11T04:48:00Z'
updated_date: '2026-11-11T05:47:00Z'
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
- [ ] #2 Not admitted in time and removed from the meeting show Teams' texts and layout
- [ ] #3 Layout, icons and actions measured from Teams desktop on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10 (219c45f): retry screen built to winpc measurements (denied: prohibited icon + title + Dismiss; removed: title, description, Dismiss then Rejoin). Verified live with OST Test 2: denied from the lobby by Teams desktop -> OST shows the denied screen; removed from the meeting -> removed screen; Rejoin -> lobby -> admitted -> connected. End reasons come from callEnd code 0 subCode 5854/5855/5000/5300.
- Open: "not admitted in time" (5855) waits on the lobby timeout run; Teams' own NotAdmittedForLongTime layout not yet seen live.
<!-- SECTION:NOTES:END -->
