---
id: TASK-0050
title: >-
  Calendar as Teams: event layout, month view, RSVP, event page, full scheduling
  form, join bar
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-17T11:01:00Z'
labels:
  - calendar
dependencies: []
references:
  - docs/parity/calendar.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Calendar P1 gaps (docs/parity/gaps-shell-calendar-files.md, docs/parity/calendar.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All-day/multi-day strip, overlapping events side by side, midnight-crossing events, Month view
- [ ] #2 RSVP (Accept/Tentative/Decline/Follow, series vs occurrence, with note) and the full event page
- [ ] #3 New meeting form with people picker, date/time pickers, rich details, location, repeat, Send vs Save; full edit of existing meetings
- [ ] #4 Meet now ▾ with Join with an ID; live meeting join bar; meeting-start notification with Join/Chat
- [ ] #5 The scheduling form's Add channel field works as Teams' (a channel meeting posts in the channel); Schedule a meeting from a channel's header opens the form with that channel filled in
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: Day, Work week and Week views with event cards (Join, Chat, Edit, Delete), a basic New meeting popup, meeting-start banners with Join and Chat, and the meeting chat's live Join. Missing: all-day and overlapping events, Month view, RSVP, the event page, the full scheduling form, Join with an ID, channel meetings. (Audit 2026-11-16)

- 2026-11-17 (41d9320): all-day strip, overlap lanes, midnight split, Month grid, card RSVP with series menus, event page (Tracking, RSVP with note, Cancel meeting), Teams' calv2 scheduling form (schedulingService/create then events), Meet now and Join with an ID dialogs, channel meetings (group calendar, channel cancel), channel header Schedule a meeting. Spec docs/spec/calendar.md; harness --cal-test.
- Verified live: Day/Work week/Week layout, RSVP with note (Graph shows Accepted), form send to a channel and its cancel.
- Open: Month view events missing in capture; Week column widths wrong when today is mid-week (future days crushed); RSVP goes through Graph (Outlook RespondToCalendarEvent refused OST's token) and Follow is missing; Join with an ID only finds meetings in your calendar; join bar and scheduled-meeting start notification not built; personal/recurring/edit sends and the channel post not yet checked live.
<!-- SECTION:NOTES:END -->
