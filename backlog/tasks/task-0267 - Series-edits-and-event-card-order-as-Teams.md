---
id: TASK-0267
title: Series edits and event card order as Teams
status: Done
assignee: []
created_date: '2026-11-24T04:18:00Z'
updated_date: '2026-11-24T05:54:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0266: choosing Does not repeat on an existing series isn't sent; Teams' Edit this and all following events isn't offered; on the event card, Add a room with Copilot sits too tight under the location, and the description comes before Prepare for this meeting where Teams has it the other way round.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Choosing Does not repeat on an existing series sends the change as Teams does
- [x] #2 Edit this and all following events is offered and sent as Teams does
- [x] #3 The event card's Add a room with Copilot spacing and the order of description and Prepare for this meeting match Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (serV) Measured on winpc (ost-test1, two series inviting OST Test 2) with screenshots, CDP DOM reads and a passive network log:
- Card Edit on your series is Edit ▾: This event / This and all following events / All events in the series.
- This and all following: "You're editing this and all following events in the series."; attendees read-only ("You can only change attendees by editing the series." + Open series); repeat shown from the occurrence's date. Send (no prompt) = UpdateCalendarEvent on the occurrence id with EventScope 2: a title change sends only Subject; a time + repeat change sends Start/End (wall times + Start/EndTimeZoneId) and Recurrence with RecurrenceRange.StartDate = the occurrence date. Exchange ends the old series before it and creates a new series.
- Does not repeat: Teams' series editor (Edit ▸ All events in the series ▸ time row) has only Repeat every N day/week/month/year, weekdays, Until + Remove end date; the Event/Series switch only on a new event. No request exists to match, so OST leaves "Does not repeat" out of the repeat menu for your series.
- Card (Outlook peek, CSS px, line = top of divider): title line, time 17 under / 7 above next line, location row 9/20/9 with "Add a room with Copilot" as the row when there is no place, organizer row 13 under (unchanged), Prepare for this meeting button 10 under (glyph 14), 32 tall, 14/600, 9 above; description 13 under (glyph 14), 14/20, 11 above; a line then Edit/Cancel 20 under, card edge 30 below. Description comes after Prepare. Copilot rows/prompts also on meetings without a Teams meeting.
- Built: MeetingForm scope (occurrence/following/series) with Outlook's info bar and links, attendees locked for following, repeat menu without Does not repeat for series, no Edit series prompt for following; card Edit ▾ menu; card rows re-spaced and reordered; calendar.rs scope field, EventScope 2, StartDate override, no attendee diff for following, series scope -> master; unit test; harness flags --cal-following, --cal-norepeat; spec + string ids. Commit d9fb8fdd.
- test2 cannot use Outlook actions (no browser sign-in) and test3 gets empty 204s, so live checks ran as ost-test1 (profile spatest, lent by the coordinator).
- Verified live on linuxlt (ost-serV, spatest): --cal-following on "OST TEST serV Q follow" 12/7: card menu has the 3 items, form shows the following banner, attendees locked, repeat "Occurs every Monday starting 12/7/2026", no Does not repeat; title + Mon/Wed -> update ok, no Edit series prompt; Graph: old series now ends 11/30, new "Q follow B" Mon+Wed 12/7-1/25; OST Test 2 got the update and has the same two series. --cal-norepeat: series page menu without Does not repeat, nothing changes or sends. --cal-peek card: rows at 69/113/151/218/269/313 and the bottom at 394 from the card top vs Teams 68/112/150/217/268/312/395 (+1 border), Add a room with Copilot as the location row, description after Prepare.
- Test data: all serV events/mails (incl. cancellations) deleted from ost-test1 (default, spatest), OST Test 2 and 3; verified none left.

- Tests: lib 945 passed, desktop 37 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's series edits and event card now match Teams desktop.

What Teams does (winpc, 2026-11-23): Edit on your series' card is Edit ▾ with This event, This and all following events, and All events in the series. "This and all following" sends UpdateCalendarEvent on the occurrence with EventScope 2. Only what changed is sent. A new repeat starts on that occurrence's date, and Exchange splits the series in two. Teams can't make a series stop repeating: its series editor has no "Does not repeat", so there is no request to copy. The card lists the place (or "Add a room with Copilot"), the organizer, Prepare for this meeting, then the description, with Outlook's spacing.

Changes:
- MeetingForm.qml: the page edits one event, this and the following events, or the series, with Outlook's info bar and links. Attendees are locked when editing following events. A series' repeat menu has no "Does not repeat". Following events are sent without the Edit series prompt.
- CalendarView.qml: Edit ▾ menu on the card. The rows are re-spaced to Teams' measurements. The description now comes after Prepare. "Add a room with Copilot" is the location row, and Copilot rows show for meetings.
- src/api/calendar.rs: a MeetingForm scope. Following events use EventScope 2, with the repeat starting on the occurrence's date and no attendee changes. Series edits go to the series master. Unit test added.
- Main.qml: --cal-following and --cal-norepeat. docs/spec/calendar.md updated, string ids regenerated.

Tests: lib 945 passed, desktop 37 passed. Live on linuxlt as ost-test1: splitting at 12/7 with a new title and Mon+Wed matched Teams (old series ends 11/30, new series Mon+Wed from 12/7), and OST Test 2 received the update. The series page offers no "Does not repeat". Card rows land within 1 px of Teams.

Not covered: Cancel ▾ for a series' events on the card; the "This event" page's exact layout wasn't re-measured; a Teams meeting's card with Copilot wasn't re-measured (the location rule was taken from meetings without a Teams meeting).
<!-- SECTION:FINAL_SUMMARY:END -->
