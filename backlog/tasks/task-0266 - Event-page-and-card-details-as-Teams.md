---
id: TASK-0266
title: Event page and card details as Teams
status: Done
assignee: []
created_date: '2026-11-24T00:59:00Z'
updated_date: '2026-11-24T04:18:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0264: Teams' event page button says Send where OST's form says Send update; a recurrence change on a repeating non-meeting event isn't sent through the new UpdateCalendarEvent path; OST's card for your own meeting lacks Teams' organizer and response row ("You're the organizer. / X didn't respond.").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The event page's send button wording matches Teams in every state
- [x] #2 Changing a repeating non-meeting event's recurrence sends the update to its attendees as Teams does
- [x] #3 The event card shows Teams' organizer and response row for your own meetings
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (evtS) Measured on winpc (ost-test1, events inviting OST Test 2/3) with screenshots, CDP DOM reads and a passive network log:
- Every event page in this Teams build (26304) is Outlook's form, Teams meetings included; calv2's "Send update" header no longer opens. New event: Save, Send (split, Save as draft) once it has attendees. Existing event: no button (a Teams meeting: Join + Chat) until something changes, then Send for a meeting (still Send after removing all attendees) or an appointment given attendees, Save for an appointment.
- Only the attendee list changed (title/times/place/repeat unchanged, attendees before and after): Outlook asks "Send update" with "Only added/removed attendees" (TargetAudience 2) / "All attendees" (1).
- Teams meetings update through the same UpdateCalendarEvent (captured a title change), not the middle tier.
- Repeat: an occurrence page says "You're editing one event in the series." (Edit series / Edit this and all following events); Edit series, new repeat, Send asks "Edit series" (Save/Cancel), then UpdateCalendarEvent on the series master with SetItemField Recurrence (WeeklyRecurrence DaysOfWeek "Tuesday Thursday", FirstDayOfWeek Sunday, Interval; EndDateRecurrence EndDate/StartDate).
- Card organizer row (Outlook PeekEventOrganizerRow, non-V2): 24 px own picture, "You're the organizer." 14 px #616161, attendee tracking 12/16 under it; one/two attendees by name, two different answers side by side, more as counts (OWA AttendeeTrackingDetails). Shown for meetings (IsMeeting, not draft), tracking while response requested and not canceled.

- Built: MeetingForm primary button per the rules above (+ send/save icons), the "Send update" audience prompt, the "Edit series" confirm, series repeat loaded into the form (event_detail returns the master's recurrence for an occurrence); send_event_update now targets the series master and sends Recurrence when the repeat changed, sends TargetAudience, and handles Teams meetings (backend routes every non-channel event there); card organizer row + tracking line.
- Verified live on linuxlt (ost-evtS, profile spatest): --cal-buttons on a plain event ("" -> Send; new Save -> Send), an appointment ("" -> Save) and a Teams meeting (Join -> Send). --cal-repeat on "OST TEST evtS series" Tue+Thu -> Tue+Fri: Edit series dialog, update ok; Graph shows the master weekly [tuesday, friday] and OST Test 2's copy updated with the update mail. --cal-audience on the Teams meeting (added OST Test 3, Only added/removed): update ok, only OST Test 3 got mail, meeting stays online with its location. --cal-peek card on "meeting two": "You're the organizer." / "OST Test 2 accepted. OST Test 3 didn't respond." as Teams.
- Test data: all evtS events/mails deleted from ost-test1, OST Test 2 and 3 (calendars, inboxes, cancellations); calQ leftovers ("Canceled: OST TEST calQ update 24" events and its invitation/update/cancellation mails) deleted from OST Test 2 and 3, and calQ sent copies from ost-test1. Verified none left.
- test3's stored token failed to refresh once (invalid_grant) during cleanup, likely two helper processes refreshing at once; launching OST as test3 refreshed it, cleanup script made sequential.
- Tests: lib 944 passed, desktop 37 passed. Commit acb68394.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The event page's primary button, repeat changes and the card's organizer row now match Teams desktop.

What Teams does (winpc, 2026-11-23): every event page is Outlook's form, Teams meetings included. A new event shows Save, then Send once it has attendees. Your own event shows no button (a Teams meeting shows Join) until you change something, then Send for a meeting and Save for an appointment. When only the attendees changed it asks "Send update" (Only added/removed attendees / All attendees). A new repeat asks "Edit series" and sends UpdateCalendarEvent with a Recurrence on the series master. Teams meetings are updated through the same request.

Changes:
- MeetingForm.qml: Teams' button rules and icons, the audience prompt (TargetAudience 2/1), the Edit series confirm, the series' repeat loaded and tracked (recurrenceChanged).
- src/api/calendar.rs: send_event_update targets the series master when the repeat changed; ews_recurrence builds Outlook's RecurrenceType; TargetAudience; a Teams meeting's location is left alone; event_detail returns an occurrence's series recurrence; unit tests.
- backend.rs: every event you organise except channel meetings updates through Outlook.
- CalendarView.qml: the card's "You're the organizer." row with your picture and Outlook's attendee tracking line.
- Main.qml: harness flags --cal-buttons, --cal-repeat, --cal-audience. docs/spec/calendar.md updated, string ids regenerated.

Tests: lib 944 passed, desktop 37 passed. Live on linuxlt: button states, a Tue+Thu -> Tue+Fri series update reaching OST Test 2, an added-attendee update reaching only OST Test 3, and the card row matching Teams.

Follow-ups not in scope: OST's card puts "Add a room with Copilot" tight under the location and the description before "Prepare for this meeting" (Teams: the other way round). Removing a series' repeat ("Does not repeat") isn't sent. Edit this and all following events isn't offered.
<!-- SECTION:FINAL_SUMMARY:END -->
