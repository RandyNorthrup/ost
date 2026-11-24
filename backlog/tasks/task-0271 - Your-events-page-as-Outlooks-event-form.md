---
id: TASK-0271
title: Your event's page as Outlook's event form
status: In Progress
assignee: []
created_date: '2026-11-24T07:41:00Z'
updated_date: '2026-11-24T08:28:00Z'
labels:
  - desktop
  - calendar
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0269: on Teams desktop (winpc, 2026-11-23) the page of your own event (This event, this and following, the series, a one-off meeting) is Outlook's event form. TASK-0269 gave OST's page Outlook's title bar, command bar card, info bar, field card and Tracking card, but the fields inside are still Teams-web (calv2) ones. Measurements: scratchpad canW form-occ.txt / form-occ-plain.txt (Teams meeting and plain occurrence) and serV form1/form2 (following, series).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The command bar has Teams' buttons (Cancel ▾, Share ▾, Duplicate, Busy ▾, Reminder ▾, Categories ▾, Private ▾, Print, …) and Copilot, Join/Chat/Send at the right
- [ ] #2 Prepare for your meeting card (Copilot) above the form when Teams shows it
- [ ] #3 Form card rows as Outlook's: charm button + title input, attendees with Tracking/Response options, one-line time with Show all instances and Scheduler, Copilot reschedule row, location with Add a room with Copilot and Location settings, Teams meeting switch with Facilitator and Options; the body in its own card with the editor toolbar and Add an agenda
- [ ] #4 Tracking card as Outlook's (Organizer with Sent on …, Attendees grouped with counts, More options and Close) and Open in new window in the title bar
- [ ] #5 Measured against Teams on winpc within 1 px
- [ ] #6 An invitation's page (an event someone else organized) is Outlook's read form as Teams shows it: Accept, Decline, Follow, RSVP with note, Propose new time, More options, Delete, Share, Duplicate, the show-as, reminder, category and privacy menus, Apps, Print, …, Join and Chat; the Prepare card; the read-only title with Sensitivity, attendees with Tracking, time with Scheduler, Add a room with Copilot, the Teams meeting switch; the body card; Tracking with You didn't respond
<!-- AC:END -->
