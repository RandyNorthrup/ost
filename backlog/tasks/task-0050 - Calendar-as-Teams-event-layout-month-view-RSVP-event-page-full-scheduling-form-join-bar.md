---
id: TASK-0050
title: >-
  Calendar as Teams: event layout, month view, RSVP, event page, full scheduling
  form, join bar
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-16T04:52:00Z'
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
<!-- SECTION:NOTES:END -->
