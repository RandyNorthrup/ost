---
id: TASK-0378
title: Ended channel meeting cards show No title and year -0001
status: Done
assignee:
  - '@t378'
created_date: '2026-11-28T00:50:00Z'
updated_date: '2026-11-28T01:49:00Z'
labels:
  - desktop
  - channels
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen during TASK-0369 live checks: in OST test channel, ended channel-meeting cards show 'No title, Sunday, December 31, -0001' instead of the meeting's title and date, which looks like a zero/unset date and missing subject being formatted. Find the source message shape and match what Teams shows for the same cards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ended channel-meeting cards in OST test channel show the same title and date as Teams desktop for the same posts
- [x] #2 A unit test covers the message shape that produced the zero date
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Dump the raw OST test channel posts (raw_messages example, ost-test1) and find the shape behind the zero date.
2. Read Teams desktop's banner rule (winpc CDP, read-only) and compare with its rendering of the same posts.
3. Fix the parse in src/api/messages.rs; unit test with the real shape.
4. Live check OST (test3 on testpc1, harness --meeting-post-test=ended) against Teams desktop.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Raw posts (raw_messages, OST test channel 19:782662e7…): the two cards come from Meet now calls (Event/Call callStarted roots 1795622872895, 1795757834064) whose properties.meeting is ScheduledMeetingCreated with meetingtitle null and scheduledmeetinginfo start/end "0001-01-01T00:00:00" (.NET zero date), which OST showed as "No title" + "Sunday, December 31, -0001".
- Teams desktop (winpc CDP, read-only) shows for those posts only the subject "Meeting in \"OST test channel\" ended" + See details, no banner. Rule from 70380/716945: the post header shows the pre-state banner only when (554704 H) scheduledMeetingInfo exists and new Date(startTime).getTime() > 1.
- Fix: scheduled_meeting() returns None unless the start is after 1970-01-01T00:00:00.001Z; unit test a_meet_now_posts_zero_date_has_no_meeting_card with the real shape.

- Live (testpc1, OST test3 under WSLg, harness --meeting-post-test=ended): both call posts parse with scheduled: null; the channel shows "Meeting in \"OST test channel\" ended" + See details for Wednesday 8:07 AM (OST Test 1) and Yesterday 9:37 PM (OST Test 3), no card, as Teams desktop on winpc (ost-test1) shows them. The real scheduled cards (OST CAL channel test / OST2, cancelled) still show with their dates.
- Unit tests (testpc1 WSL): a_meet_now_posts_zero_date_has_no_meeting_card, reads_a_scheduled_meetings_post pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ended Meet now posts in a channel no longer show a "No title, Sunday, December 31, -0001" calendar card.

Cause: a Meet now in a channel posts its call (Event/Call callStarted) with properties.meeting as ScheduledMeetingCreated, meetingtitle null and scheduledmeetinginfo start/end "0001-01-01T00:00:00" (.NET zero date). OST built a ScheduledMeetingCard from it.

Fix (src/api/messages.rs): scheduled_meeting() returns None unless the start is after the epoch, Teams' rule for the post header's pre-state banner (554704 H: scheduledMeetingInfo and new Date(startTime).getTime() > 1). The post keeps its "Meeting in … ended" subject and See details.

Tests: unit test with the real message shape (zero date, epoch, unreadable and missing starts get no card; a real start keeps it). Harness --meeting-post-test=ended logs the channel's call posts and cards.

Live: testpc1 (OST test3) vs Teams desktop on winpc (ost-test1): same subject and times, no card in either.
<!-- SECTION:FINAL_SUMMARY:END -->
