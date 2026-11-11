---
id: TASK-0106
title: >-
  Call-ended screens as Teams (denied from lobby, removed, not admitted, meeting
  ended)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-11T04:48:00Z'
updated_date: '2026-11-11T04:50:00Z'
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
- [ ] #1 Denied from the lobby: OST shows Teams' screen with its icon and "Sorry, but you were denied access to the meeting.", verified live with a second account
- [ ] #2 Not admitted in time and removed from the meeting show Teams' texts and layout
- [ ] #3 Layout, icons and actions measured from Teams desktop on winpc
<!-- AC:END -->
