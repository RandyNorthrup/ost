---
id: TASK-0271
title: Your event's page as Outlook's event form
status: Done
assignee: []
created_date: '2026-11-24T07:41:00Z'
updated_date: '2026-11-24T10:54:00Z'
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
- [x] #1 The command bar has Teams' buttons (Cancel ▾, Share ▾, Duplicate, Busy ▾, Reminder ▾, Categories ▾, Private ▾, Print, …) and Copilot, Join/Chat/Send at the right
- [x] #2 Prepare for your meeting card (Copilot) above the form when Teams shows it
- [x] #3 Form card rows as Outlook's: charm button + title input, attendees with Tracking/Response options, one-line time with Show all instances and Scheduler, Copilot reschedule row, location with Add a room with Copilot and Location settings, Teams meeting switch with Facilitator and Options; the body in its own card with the editor toolbar and Add an agenda
- [x] #4 Tracking card as Outlook's (Organizer with Sent on …, Attendees grouped with counts, More options and Close) and Open in new window in the title bar
- [x] #5 Measured against Teams on winpc within 1 px
- [x] #6 An invitation's page (an event someone else organized) is Outlook's read form as Teams shows it: Accept, Decline, Follow, RSVP with note, Propose new time, More options, Delete, Share, Duplicate, the show-as, reminder, category and privacy menus, Apps, Print, …, Join and Chat; the Prepare card; the read-only title with Sensitivity, attendees with Tracking, time with Scheduler, Add a room with Copilot, the Teams meeting switch; the body card; Tracking with You didn't respond
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24: measured Teams on winpc (CDP + VNC): one-off Teams meeting M1, weekly series S1 (one event, this and following, series), OST Test 2's invitation I1; every command bar menu, Response options, Location settings, Tracking's More options, the time panel (one-off and series), Prepare card's More suggestions. Findings in docs/spec/calendar.md.
- Invitation page is Outlook's read form too: AC #6 added and built.
- Built: Outlook's command bar per kind (Event | Series, Cancel, Share, Duplicate, Busy, Reminder, Categories, Private, Apps, Print, …; invitation: Accept/Decline/Follow/RSVP with note/Propose new time/More/Delete…), Copilot button, Prepare card, the form card rows, time panel, body card with its toolbar and Add an agenda, Tracking card, Open in new window (the form moves into its own window and back).
- Busy/Reminder/Categories/Private save at once (Outlook saves them without Send, checked on winpc); reminder and Response options need patch_event's new keys.
- Harness: --cal-page, --cal-page-menus, --cal-page-set, --cal-page-popout.

- Verified live on linuxlt as ost-test1 (2026-11-24): --cal-page for M1 (one-off Teams meeting), S1 as one event, this and following and the series, and I1 (invitation); layouts set against Teams' DOM measurements: every fixed position (cards, rows, lines, fields, buttons placed from the right, Tracking) within 1 px. Positions that follow a text's width differ by the font: OST draws Selawik where Teams has Segoe UI, about 2 px per 14 px label (regular narrower, semibold wider), so command bar buttons after Event/Series/Cancel sit up to ~6 px left of Teams'; with Segoe UI installed the same rules give Teams' numbers.
- Menus (Share, Busy, Reminder, Categories, Private, …, Response options, Location settings, Tracking More options) captured; Open in new window pops the page out and back.
- Live saves: Busy → Free → Busy and Reminder 30 → 15 from the page, read back from Graph.
- Tests: cargo test --features audio,video --lib 951 passed; desktop 37 passed.
- Follow-ups: TASK-0274 (time suggestions), TASK-0275 (Allow forwarding, Rebook declined rooms, Copilot reschedule, Add email reminder, New category, body tools natively), TASK-0276 (charm of events made in Teams).
- Test data: frmX events and mails deleted from ost-test1, OST Test 2, OST Test 3 (0 left).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Your event's page and an invitation's page are now Outlook's event form, as Teams desktop shows them (measured on winpc 2026-11-24).

Changes:
- Command bar per kind: Event | Series, Cancel (▾ on one event of a series), Share ▾, Duplicate, Busy ▾, Reminder ▾, Categories ▾, Private ▾, Apps, Print, … ; an invitation's Accept, Decline, Follow, RSVP with note, Propose new time, More options ▾, Delete … ; Join/Chat/Send and Copilot's button. Show as, reminder, categories and privacy save at once (Graph PATCH), as Outlook does.
- Prepare for your meeting card (Copilot chips, More suggestions); the fields' card with Outlook's rows (charm + title, attendee pills with Tracking and Response options, time line or series sentence with Show all instances and Scheduler, Copilot reschedule row, Add a room with Copilot + location + Location settings, Teams meeting switch with Facilitator and Options); the time panel; the body card with Outlook's toolbar and Add an agenda; an invitation's read-only fields.
- Tracking card as Outlook's (Organizer with Sent on, You didn't respond, answer groups, More options: search, sort, copy, CSV) and Open in new window (the page moves to its own window and back).
- Backend: event detail reads created time, reminder, Response options; patch_event takes reminder/responseRequested/hideAttendees; saveCsv action.
- Harness: --cal-page, --cal-page-menus, --cal-page-set, --cal-page-popout. Spec (docs/spec/calendar.md), docs, Fluent icons, string ids.

Tests:
- cargo test -j 8 --features audio,video --lib (951 passed); desktop crate (37 passed).
- Live as ost-test1: layouts of a one-off meeting, a series (one event, this and following, series) and an invitation set against Teams' DOM measurements; menus captured; pop-out; Busy and Reminder saved and read back from Graph.

Known gaps: text-width-driven positions follow Selawik (≈2 px per label vs Segoe UI); follow-ups TASK-0274, TASK-0275, TASK-0276.
<!-- SECTION:FINAL_SUMMARY:END -->
