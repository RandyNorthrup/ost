---
id: TASK-0050
title: >-
  Calendar as Teams: event layout, month view, RSVP, event page, full scheduling
  form, join bar
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-17T16:42:00Z'
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
- [x] #1 All-day/multi-day strip, overlapping events side by side, midnight-crossing events, Month view
- [x] #2 RSVP (Accept/Tentative/Decline/Follow, series vs occurrence, with note) and the full event page
- [x] #3 New meeting form with people picker, date/time pickers, rich details, location, repeat, Send vs Save; full edit of existing meetings
- [x] #4 Meet now ▾ with Join with an ID; live meeting join bar; meeting-start notification with Join/Chat
- [x] #5 The scheduling form's Add channel field works as Teams' (a channel meeting posts in the channel); Schedule a meeting from a channel's header opens the form with that channel filled in
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: Day, Work week and Week views with event cards (Join, Chat, Edit, Delete), a basic New meeting popup, meeting-start banners with Join and Chat, and the meeting chat's live Join. Missing: all-day and overlapping events, Month view, RSVP, the event page, the full scheduling form, Join with an ID, channel meetings. (Audit 2026-11-16)

- 2026-11-17 (41d9320): all-day strip, overlap lanes, midnight split, Month grid, card RSVP with series menus, event page (Tracking, RSVP with note, Cancel meeting), Teams' calv2 scheduling form (schedulingService/create then events), Meet now and Join with an ID dialogs, channel meetings (group calendar, channel cancel), channel header Schedule a meeting. Spec docs/spec/calendar.md; harness --cal-test.
- Verified live: Day/Work week/Week layout, RSVP with note (Graph shows Accepted), form send to a channel and its cancel.
- Open: Month view events missing in capture; Week column widths wrong when today is mid-week (future days crushed); RSVP goes through Graph (Outlook RespondToCalendarEvent refused OST's token) and Follow is missing; Join with an ID only finds meetings in your calendar; join bar and scheduled-meeting start notification not built; personal/recurring/edit sends and the channel post not yet checked live.

- 2026-11-17 (calendar follow-up merged): Month asked for one day of events; the range now comes from the view. Week widths keep each future day at least one event wide. Follow = Tentative + attendance Follow. Outlook's RespondToCalendarEvent needs the hosted calendar's token (app ceb96695 via the broker); the calendar service's respond call is the fallback, and Graph is no longer used.
- Join with an ID resolves the ID and passcode through the conversation service, as Teams. The MeetingStart notification drives the scheduled-meeting banner and the join bar, using Teams' rules.
- Live: personal recurring meeting with test2, edit through Teams' own update request, channel header Schedule a meeting, channel post and cancel.
- Left: measure the join bar layout and Week-with-lanes widths on winpc, and run OST itself through the Outlook RSVP path (the default profile is back on teams-web). Both are with the agent.

- 2026-11-17 (final round): Teams desktop measured on winpc. Up to 1550 px wide all days are equal with short names. Above it, in the week holding today, today is 1.5 times an equal share and tomorrow 1.3 times. Side-by-side events never widen a day.
- Join bar: brand-tinted, Join or View meetings. Live meetings dialog built. Live Join on tiles. A meeting that starts after the calendar loaded is looked up, as Teams does.
- RSVP goes through Outlook RespondToCalendarEvent with the hosted calendar token whenever the sign-in is the browser one; verified live for Tentative, Accept with note, Follow, Decline and an occurrence. Device-code profiles fall back to Teams' calendar service.
- Main-thread check on the merged build: Week at 1280 shows equal columns, and the form opens clean.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Calendar works as in Teams desktop: week and month layouts, invitations, the event page, Teams' scheduling form, Meet now, Join with an ID, the join bar and channel meetings.

Changes:
- CalendarView.qml:
  - all-day strip, overlap lanes, midnight split;
  - Teams desktop's width rule for days (equal below 1550 px; above it today x1.5, tomorrow x1.3);
  - Month view with "+N";
  - busy bars, series icons, live Join on tiles.
- MeetingForm.qml: Teams' calv2 form, with people picker and free/busy, pickers, All day, repeat and Set recurrence, Add channel, location, rich details, Options, and Send / Save / Send update. Also the event page, with Tracking, RSVP with note and Cancel meeting.
- LiveMeetingsDialog.qml: Teams' "View meetings" dialog.
- src/api/calendar.rs:
  - schedules through schedulingService/create and then events, as Teams;
  - channel meetings go in the team's group calendar, with a channel cancel;
  - edits and cancels use Teams' own update request;
  - free/busy and Meet now;
  - RSVP and Follow through Outlook RespondToCalendarEvent with the hosted calendar's token, falling back to Teams' calendar service.
- Calling: Join with an ID resolves the ID and passcode through the conversation service, as Teams. MeetingStart drives the start banner and the join bar under Teams' rules.
- Channel header Schedule a meeting.
- Spec docs/spec/calendar.md; harness --cal-test and its options (docs/desktop.md).

Tests:
- cargo test --features audio,video --lib: 692 passed.
- Verified live as ost-test1 and test2:
  - layouts, Month and the busy week;
  - every RSVP kind through Outlook;
  - a personal recurring meeting, an edit, and a channel meeting with its post and cancel;
  - Join with an ID for an uninvited meeting;
  - the banner, the join bar and the Live meetings dialog.

Follow-up: TASK-0220 (Filter, Time scale, Saved views, Split view, propose new time, Event form, live avatars, Copilot parts).
<!-- SECTION:FINAL_SUMMARY:END -->
