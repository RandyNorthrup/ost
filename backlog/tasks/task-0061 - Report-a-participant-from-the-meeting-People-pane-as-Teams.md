---
id: TASK-0061
title: Report a participant from the meeting People pane, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T20:04:00Z'
updated_date: '2026-11-09T08:39:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' participant ··· menu ends with Report (shield glyph), which opens Teams' report-a-concern flow for that participant. OST's menu matches Teams except for this item. No real reports may be filed while testing: verify up to the final submit only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The participant menu shows Report last, as Teams does
- [x] #2 Report opens Teams' dialog with the same choices and text, measured from Teams
- [x] #3 Submitting sends the same request Teams sends (verified from Teams' code, not by filing a real report)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc: participant ··· menu ends Remove from meeting, Report (shield glyph); Report opens "Report this person" (report-meeting-dialog in its person mode): 600 x 359.33, participant card 48 px (#F5F5F5, shadow2), explanation, counter, footer, Cancel/Report.
- Teams' code (meet-app-modal, meet-for-work resolver): same reportMeetingToUnified body, reportedUsers = [that person], category Security. OST's report_meeting already sends that body (unit-tested).
- Fixed on the way: the failure text sits under the card in Teams (no icon, red 14/20, 12 margin); both cards have shadow2.
- Verified live (--join-report-person): menu with Report last, dialog layout compared with winpc; never submitted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Report a participant from the meeting People pane, as Teams.

Changes:
- PeoplePane: Report (shield) ends the participant ··· menu in scheduled meetings.
- MeetingReportDialog: "person" mode (Report this person: the participant card in place of the meeting card, no picker), reporting that one person with Teams' unified report body.
- Failure text placed and styled as Teams' code (under the card, red, no icon); cards get Fluent's shadow2.
- Spec updated.

Tests: live --join-report-person run (menu and dialog compared with winpc). No report filed (rule).
<!-- SECTION:FINAL_SUMMARY:END -->
