---
id: TASK-0261
title: Attendance from a chat's recap card as Teams
status: In Progress
assignee:
  - '@copY'
created_date: '2026-11-23T18:09:00Z'
updated_date: '2026-11-23T19:24:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0257: a recap window opened from a meeting chat's recap card opens Attendance inside that chat; Teams' behaviour there wasn't checked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Attendance in a recap window opened from a chat's recap card opens where Teams opens it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams on winpc 2026-11-23: OST TEST 240 recap meeting chat > card Recap opens the recap window; its Shared files > Attendance opens the meeting chat in a NEW window (1283x730, titled with the meeting, header with Join/roster/Copilot/Find/details/more, then the attendance report, no tabs). Same as TASK-0257 from Recaps Home; main window unchanged.

- Fixed: Conversation.openRecap now connects the recap window's Attendance to attendanceOf(thread, subject) (TASK-0257's chat window on its Attendance report) instead of opening Attendance inside the chat.
- Verified live on linuxlt (ost-test1): --recap-window-test=attendance --recap-chat=OST~TEST~240~recap~meeting: the recap window lists Attendance; pressing it opened "OST TEST 240 recap meeting" chat window 1283x730 on the Attendance tab with no tab row (2 attended, 8:25-8:32 PM, OST Test 1/3); the main window stayed on the chat with no tab change.
<!-- SECTION:NOTES:END -->
