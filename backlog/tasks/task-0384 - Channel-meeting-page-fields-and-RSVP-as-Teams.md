---
id: TASK-0384
title: Channel meeting page fields and RSVP as Teams
status: To Do
assignee: []
created_date: '2026-11-28T07:52:00Z'
labels:
  - desktop
  - channels
  - calendar
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen side by side for TASK-0381 (Teams desktop on testpc1 as ost-test1 and testpc2 as OST Test 2, 2026-11-27; "Design review" in OST Test Team ▸ General). The command bars match now; the rest of the channel meeting page still differs:
- Organizer page: Teams shows "Optional:" as a label before the chips in one box under "Add required attendees"; OST shows a separate tall box. Teams keeps "Microsoft Teams Meeting" as a location chip (Unknown); OST shows an empty "Add location". Teams' tabs are Chat, Details, Scheduling Assistant, Recap, Attendance, +3; OST's are Chat, Details, Scheduling Assistant.
- Read-only (team calendar) page: OST writes "OST Test 1" in the attendee field; Teams shows no attendee field there. Teams' Tracking lists "OST Test 1 Organizer" then "Optional / OST Test 2 Accepted".
- Invitation of a channel meeting (in your calendar): Teams answers with one "Accepted ▾" menu button; OST shows Accept, Tentative, Decline, Follow and RSVP with note.
- The organizer form doesn't list rooms (resources); a channel meeting update keeps them, but there is no way to remove one from OST.
Built so far: TASK-0381 made the organizer page editable, the bars as Teams (Cancel meeting | Copy link, Show as greyed; Add to calendar | Copy link, Forward, Show as).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The organizer page's attendee box, location and tabs match Teams desktop
- [ ] #2 The team-calendar page shows no attendee field, as Teams
- [ ] #3 A channel meeting invitation answers with Teams' single response menu
- [ ] #4 Rooms on a channel meeting show and can be removed as in Teams
<!-- AC:END -->
