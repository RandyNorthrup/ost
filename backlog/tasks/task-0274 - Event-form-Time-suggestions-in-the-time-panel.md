---
id: TASK-0274
title: 'Event form: Time suggestions in the time panel'
status: Done
assignee: []
created_date: '2026-11-24T10:07:00Z'
updated_date: '2026-11-24T13:24:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0271: Outlook's event form (Teams' event page) lists Time suggestions under the time panel's fields (rows 715.67 x 40, 48 apart: the day 12/600, the time and length 12 px, how many are free; a series: 'Occurs every Thursday …' with % available). OST's time panel has the fields, All day, Recurring and the repeat, but no suggestions yet. Measurements: docs/spec/calendar.md (time panel).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The time panel lists Teams' time suggestions for the attendees, as Teams does for a one-off event and a series
- [x] #2 Picking a suggestion sets the event's time
- [x] #3 Measured against Teams on winpc within 1 px
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (frmY): captured on winpc: Outlook's form asks `POST outlook.office.com/SchedulingB2/api/v1.0/me/findmeetingtimes` (x-findmeetingtimes-appscenario: suggestions, x-isupdateevent): one event a timeslot from its start to +9 days with queryExpression "Date:<start>..<start+5d>"; a series patternedRecurrence; meetingDuration, minimumAttendeePercentage 100, maxCandidates 5. Answers in UTC.
- Built: event_form::find_meeting_times; the time panel's Time suggestions (heading, ⓘ "The best options in a 5-day window", rows 715.67 x 40, 48 apart; one event "Tue 12/1  10:30 AM - 11:00 AM (30 min)" with the free count, a series "Occurs every Thursday … 100% available"); asked again when times, attendees or repeat change; picking one sets the times (a series keeps its repeat); the panel scrolls (245 / 289 tall as Teams).
- Verified live as ost-test1 (frmY Y1 one-off, Y2 weekly series as the series): suggestions identical to Teams on winpc (Y1: Tue 12/1 10:30 AM first, 3 available; Y2: Occurs every Thursday 8:00 AM - 8:30 AM, 100% available); picking sets 11:00-11:30 / 8:00-8:30 and Send appears. Layout against Teams' DOM: heading, rows, glyphs, date, (30 min) and the right edge within 1 px; positions after a text follow Selawik's widths (about 2 px, as TASK-0271 notes).

- Commit d74e188d (worktree agent-ad0592ee48b5c8882). Tests: lib 957 passed, desktop 37 passed. Test data deleted from all three accounts (0 left).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Time suggestions in the event page's time panel, as Outlook's form in Teams desktop shows them (captured on winpc 2026-11-24).

Changes:
- event_form::find_meeting_times: Outlook's SchedulingB2 findmeetingtimes with the hosted calendar's token and its headers; one event from its start over 9 days with the 5-day query, a series by its pattern; answers parsed as UTC times with the free count and share.
- MeetingForm's time panel: "Time suggestions" with ⓘ, rows as Teams' (one event: day, times, length, free count; a series: "Occurs every …", "100% available"), asked again on changes, picking one sets the times; the panel scrolls at Teams' heights.

Tests:
- Live as ost-test1: a one-off meeting and a weekly series give the same suggestions as Teams on winpc; picking sets the times; layout within 1 px of Teams' DOM except text-width-driven positions (Selawik vs Segoe UI).
- cargo test --lib (957), desktop (37).
<!-- SECTION:FINAL_SUMMARY:END -->
