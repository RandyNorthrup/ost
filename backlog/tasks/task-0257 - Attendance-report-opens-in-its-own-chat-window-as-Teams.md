---
id: TASK-0257
title: Attendance report opens in its own chat window as Teams
status: Done
assignee:
  - '@attW'
created_date: '2026-11-23T16:22:00Z'
updated_date: '2026-11-23T18:08:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0253: in Teams, clicking Attendance under a recap window's Shared files opens the meeting chat in a separate chat window on its Attendance report. OST opens it in the main window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking Attendance in a recap window opens the meeting chat in its own window on the Attendance report, as Teams
- [x] #2 The pop-out chat window behaves as Teams' (size, title, tabs, closing)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams 26304 on winpc: the recap window's Attendance pop-out (size, title, header, tabs, reuse, closing); read the click path in the bundles
2. ChatWindow: an Attendance mode (the meeting chat's header over its Attendance view, no tabs, 1283 x 730), its own meeting (Conversation.ownMeeting from events_request chatMeeting) instead of the main window's
3. Main: a recap window's Attendance opens / raises that window instead of selecting the chat
4. Harness --recaps-home checks the window; live on linuxlt vs Teams; docs, tests
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (attW) Teams 26304 on winpc (CDP, read only + VNC): Attendance under a recap window's Shared files calls meetingAnalytics.openAttendanceTabInMeetingRecapOfChat (stateTransition new while isRecapInPopout) -> a new window, cascaded on the recap window, 1283.33 x 730 CSS (the recap window's size), titled with the meeting (title row "OST TEST 240 recap meeting", OS title "<meeting> | Microsoft Teams").
- Inside: Teams' child-window title row (32; Settings and more 24 x 23.33 at 1115.67), then the meeting chat's header (entity-header, 61, white, 0.67 #E0E0E0 under it: the meeting picture 32 at 20,14; the title 18/700/25.7 at 60; Join, participants (2), Copilot, Find in chat, Open chat details, More chat options -> View Copilot history, Mark as unread, Move to section, Mute, Copy link, Report a concern, no Open in new window), then straight to the Attendance view (meeting-attendance-view-wrapper at y 93): no tab row, no chat or compose.
- Pressing Attendance again with the window open opens no second one. Escape doesn't close it; only the window's close does, and the recap window stays.

- Teams' chat header hides Meeting details while the tabs are hidden (chat-app Lg: Ng(…, enableChatHeaderMeetingDetailsButton || !areTabsHidden)), so the pop-out has none.
- Built: ChatWindow `attendance` (1283 x 730 once, title = the chat's name or the recap's subject; the report once its meeting is known; showAttendance() when the chat's window is already open); Main openChatWindow(…, attendance) from Conversation.openChatForAttendance (attendanceOf no longer opens it in the main window; attendanceWanted gone). Pop-out Conversations read their own meeting and members (events_request chatMeeting / chatMembers -> windowMeeting / windowMembers; `chatMembers` replaces the main window's chat_members_json in Conversation): before, a pop-out meeting chat showed the main window's meeting (no Join, no Attendance) and its roster count. Meeting details hidden in a pop-out without tabs. Harness --recaps-home steps 416-418.
- Live (linuxlt, ost-test1, --recaps-test --recaps-home): main window stays on Meeting Recaps (no chat selected); window 1283 x 730 "OST TEST 240 recap meeting", tab Attendance, no tab row, report at y 93 (Teams 93) 1283 x 637, same report as Teams (2 attended, 8:25-8:32 PM, 6m 26s, 5m 23s, OST Test 1 Organizer / OST Test 3 Presenter); header Join, roster 2, Find in chat, chat details, More (Teams also has Copilot: OST's chat header has no Copilot button anywhere yet, docs/parity/chat.md). Pressed again: chat windows 1 -> 1, same window. Closed: gone, recap window still open.

- Tests: 931 lib + 35 desktop on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A recap window's Attendance now opens the meeting chat in a window of its own on its Attendance report, the way Teams does (openAttendanceTabInMeetingRecapOfChat). Before, OST switched the main window to the chat.

- ChatWindow `attendance`: the window is 1283 x 730, like the recap window and Teams' pop-out, and is titled with the meeting chat. It shows Teams' child-window title row, then the chat header (Join, roster, Find in chat, chat details, More), then the Attendance view at y 93. There is no tab row, no messages and no compose. Pressing Attendance again brings the same window forward. Only the window's close closes it, and the recap window stays open.
- Pop-out Conversations now load their own chat's meeting and members (events_request `chatMeeting` / `chatMembers`). Before, they used the main window's chat: a pop-out meeting chat had no Join and no Attendance, and its roster count was wrong. Meeting details is hidden in a pop-out with no tab row, as Teams does (enableChatHeaderMeetingDetailsButton || !areTabsHidden).
- Harness `--recaps-home` checks the window, a second press and closing (docs/desktop.md). docs/spec/events.md has the measurements.

Verified live on linuxlt (ost-test1, OST TEST 240) against Teams 26304 on winpc: same size, title, header and report (2 attended, 8:25-8:32 PM, 6m 26s, 5m 23s); the main window stays on Meeting Recaps.
Still open: Teams' chat header also has Copilot, which OST's chat header lacks everywhere (docs/parity/chat.md).

Tests: 931 lib + 35 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
