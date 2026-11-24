---
id: TASK-0269
title: Series Cancel menu and event page layouts as Teams
status: Done
assignee: []
created_date: '2026-11-24T05:55:00Z'
updated_date: '2026-11-24T08:04:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0267: the event card's Cancel ▾ for a series (this event / this and following / all) isn't built; the 'This event' page layout wasn't re-measured; a Teams meeting's card with the Copilot rows wasn't measured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cancel on a series' card offers Teams' choices and cancels each as Teams does, verified with attendees
- [x] #2 A Teams meeting's card matches Teams' layout, measured on winpc
- [x] #3 The This event page is re-measured on winpc; its title bar, command bar card, info bar and cards follow Teams, and Outlook's form rows inside move to TASK-0271
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (canW) Measured on winpc (ost-test1; series T1 Teams meeting, T2/T3 plain, S1 one-off Teams meeting, all inviting OST Test 2/3) with CDP DOM reads and a passive netlog:
- Card Cancel on a series: Cancel ▾ This event / This and all following events / All events in the series (Outlook ContextualMenu 194.33 wide, 36 px rows). Picking one (or Cancel on a one-off) turns the Edit/Cancel row into "Cancel [this event|this and all following events|all events in the series|event] and notify attendees", a 320x72 message box and Send/Discard; the card keeps its bottom edge.
- Send = Outlook CancelCalendarEvent: EventScope 1 (this event, one-off too, own id), 2 (following, occurrence id), 3 (all, series master id); Notes HTML <div>msg</div> only with a message. Teams meetings the same (no middle tier). Attendees get "Canceled: <subject>" with the message.
- Event page Cancel (▾ on a series) opens Outlook's "Cancel meeting" dialog (600 wide, same header/box/Send/Discard).
- Teams meeting card: charm before the title, Join ▾ (Join Teams meeting / Copy join link), "No location added" + "Add a room with Copilot" under it, no description row for the join block, no "key talking points" prompt while live.
- This event page (Outlook form): 48 px title bar "<subject> - Event instance", command bar card, info bar, Prepare card, form card, body card, Tracking card; OST's page is still Teams-web calv2 layout.

- Built (c94498dc): card Cancel ▾ (series) / Cancel (one-off) -> Teams' cancel message (header per scope, 320x72 box, Send/Discard, card keeps its bottom edge); Outlook CancelCalendarEvent (cancel_event: EventScope 1/2/3, master id for the series, HTML Notes only with a message) for every non-channel event, card and page; page Cancel ▾ + Outlook "Cancel meeting" dialog; Teams meeting card (charm, Join ▾ Join Teams meeting/Copy join link, Join 77/Chat 96, No location added + Add a room with Copilot, join block not shown as description, no talking-points prompt while live); card menus as Outlook's ContextualMenu; your event's page gets Outlook's title bar, command bar card, info bar buttons, field card and Tracking card; harness --cal-card-cancel, --cal-page-cancel, --cal-no-send; unit test; spec, docs, string ids.
- Verified live on linuxlt as ost-test1 (profile default): card This event on "OST TEST canW O1" 12/3 with a message (occurrence gone; Graph series intact), card This and following from 12/17 (series now ends 12/10), card All events on the Teams meeting series O2 without a message (all gone), card Cancel on one-off Teams meeting O4, page Cancel meeting on one-off O3 and page This and following on T3 from 12/15 (series ends 12/8). OST Test 2 and 3 got "Canceled: <subject>" with the message (this event, all, one-off) and an update carrying the message for this-and-following (as Exchange does when events remain). Card rows of the Teams meeting land within 1 px of Teams (Join 69, line 117, time 135, location 170/192, organizer 235, Prepare 297, cancel header 329, box 354/356, Send 438/440).
- Page: re-measured; Outlook's form fields inside (Prepare card, one-line time, Show all instances, Copilot rows, full command bar, Open in new window) aren't built: follow-up TASK-0271.
- Test data: all canW events and mails deleted from ost-test1, OST Test 2 and 3 (second pass found none). test3's stored token failed to refresh once; launching OST as test3 refreshed it.

- Tests: lib 946 passed, desktop 37 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cancelling your events now works like Teams desktop: Cancel on a series' card offers This event, This and all following events and All events in the series, and the Teams meeting card matches Teams'.

What Teams does (winpc, 2026-11-23): Cancel on a meeting's card (▾ with the three choices on a series) swaps the Edit/Cancel row for "Cancel … and notify attendees", a message box and Send/Discard. Send is Outlook's CancelCalendarEvent with EventScope 1 (this event, a one-off too), 2 (this and following, on the occurrence) or 3 (all, on the series master), and HTML Notes when a message was typed. Teams meetings take the same path. The event page's Cancel opens Outlook's "Cancel meeting" dialog. Attendees get "Canceled: <subject>" with the message.

Changes:
- src/api/calendar.rs: cancel_event / cancel_event_request (Outlook's request, scopes, notes); cancel_meeting keeps the middle tier only for channel meetings; unit test.
- CalendarView.qml: card Cancel ▾ and the cancel message (keeps the card's bottom edge); Outlook-style scope menus; Teams meeting card (charm, Join ▾ with Join Teams meeting / Copy join link, Join 77 / Chat 96, No location added + Add a room with Copilot, join details not shown as the description, no talking-points prompt while live); layout dump for the harness.
- MeetingForm.qml: Cancel ▾ on a series and Outlook's Cancel meeting dialog; your event's page gets Outlook's title bar, command bar card (Cancel, Busy, Send/Join/Chat), info bar buttons, field card and Tracking card.
- backend.rs passes the scope; Main.qml --cal-card-cancel, --cal-page-cancel, --cal-no-send; docs/spec/calendar.md, docs/desktop.md, string ids.

Tests: lib 946 passed, desktop 37 passed. Live as ost-test1 on linuxlt: card This event, This and following, All events (Teams meeting series), one-off Teams meeting, page one-off and page This and following; Graph and OST Test 2/3's mail match Teams'. The card rows are within 1 px of Teams'.

Follow-up: TASK-0271 (the fields inside your event's page as Outlook's form; Prepare card, one-line time, Copilot rows, full command bar, Open in new window).
<!-- SECTION:FINAL_SUMMARY:END -->
