---
id: TASK-0109
title: Meeting attendance report card (Attendance) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T07:22:00Z'
updated_date: '2026-11-11T15:58:00Z'
labels:
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Under a meeting's end Teams shows an Attendance card (attendance-report-message-wrapper: 321.3 x 49.3, #E6E6E6, radius 4, a 32 px icon and "Attendance"), in meeting chats and in a channel meeting's thread. Clicking it opens Teams' native Attendance view (meeting-attendance-view-wrapper, measured on winpc 2026-11-11): an occurrence picker ("Tuesday, November 10, 2026 8:55 PM - 8:57 PM"), More (filter), Download; summary cards (Attended, Start and end time, Meeting duration, Average attendance time); a Participants table (Name with email, First join, Last leave, In-meeting duration, Role). OST shows the end row without the card.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Meeting chats and channel meeting threads show Teams' Attendance card under a meeting's end, measured on winpc
- [x] #2 Clicking the card opens Teams' Attendance view with its summary, occurrence picker and Participants table from the live report
- [x] #3 Download saves the attendance report as Teams does (verified with the test meetings)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11 (7babadb): card shown to organizer/co-organizers (thread meeting organizerId/coOrganizerIds, not Broadcast) under ended meetings in meeting chats and channel meeting threads; opens Teams' native Attendance view (meeting-chat tab; channel full content). Endpoints captured from Teams: attendancereport/history, attendancereport, attendancereport/file (aud c82e1b1b-…, AttendanceReport.Read). A chat's call id is the report's ngcCallId (mapped).
- Verified live as OST Test 1: test meeting chat (11 reports) and the channel meeting; Download saved the service's file (UTF-16 TSV, its own name).
- Not done: Teams' title-bar Downloads button (OST reports saves in its status line, as for other downloads); co-organizers of channel meetings (OST checks the organizer only there).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' Attendance card and Attendance view, native.

Changes:
- AttendanceCard under ended meetings for organizers and co-organizers (meeting chats and channel meeting threads), measured on winpc.
- AttendanceView: meeting picker grouped by day, More (attendee-count filter), Download, summary cards and Participants table; a tab in meeting chats, the full content area for channel meetings (back returns).
- api::attendance (history, report, file) with the attendance service's token; ThreadMeeting gains coOrganizerIds and meetingType; backend load_attendance / download_attendance_report.
- Spec in docs/spec/channel-meetings.md; NOTICE for the card glyph.

Tests:
- 431 lib tests (URLs, id checks, Content-Disposition names, meeting parsing).
- Live: --attendance-test against the test meeting chat and channel meeting, compared with Teams on winpc; report file downloaded and named as Teams names it.
<!-- SECTION:FINAL_SUMMARY:END -->
