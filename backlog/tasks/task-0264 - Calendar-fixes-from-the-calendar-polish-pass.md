---
id: TASK-0264
title: Calendar fixes from the calendar polish pass
status: Done
assignee:
  - '@calQ'
created_date: '2026-11-23T21:21:00Z'
updated_date: '2026-11-24T00:59:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0262: Teams' high contrast calendar draws yellow event tiles where OST draws black; OST's calendar toolbar shows "Filter applied" for ost-test1 where Teams shows no filter; Send update on a non-meeting event fails with "Conversation id cannot be null".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 High contrast calendar event tiles match Teams' colours in every view
- [x] #2 The calendar toolbar shows Filter applied only when Teams does, with the same filter state
- [x] #3 Send update on a non-meeting event sends the update to its attendees as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (calQ) Measured on winpc over CDP and screenshots with 8 test events in ost-test1's week (busy, free, tentative, working elsewhere, away, ended, all-day, and one inviting OST Test 2): Teams in High contrast 14:00-14:03 winpc time (Day, Work week, Week, Month, the card), then back to "Follow operating system theme" (checked light).
- High contrast: Teams' "contrast" palette for the hosted frame (owa TeamsPalette) has themePrimary #FFF200 and white #000, so the tiles are the dark model on #FFF200: busy #999100 / free, tentative, elsewhere and ended #4D4900 at 90 %, text #000000 / #E6E6E6 (Month #FFFFFF, ended #BEBEBE); bars #FFF200; dates, today bar, now line, Month today circle and border, card top edge #FFF200; lines #5C5C5C, dashes #141414, busy all-day day #1A1800; selected ring #FFFFFF; card #000 with #5C5C5C edge and lines, links #7F85F5; mini month range #383966, today #4F52B2.
- Show-as bars (owa module 881574, checked in light): Away is freeBusyAwayColor (#B4009E, dark/HC #F500D8) crosshatched with the day colour at 80 %; Working elsewhere is open with calendar-colour dots. OST drew both as busy.
- Card icons: Edit #5B5FC7 light / #0F6ABA HC, Delete/Cancel #E81123 light and HC.
- Filter: Teams on winpc shows "Filter applied" for ost-test1 too (in "…", Reservations unchecked, everything else checked). ost-test1's calendar_filters roaming value is [["Reservations",["Desk"]]]; Teams' label is "Filter applied" whenever the filter map is non-empty, and it unchecks Desk once per device (olk-UnselectedReservationFilter=Desk in its localStorage) under flights cal-filterUXRefresh and msplaces-space-finder-vnext. OST already reads the same setting and shows the same state, so no code change.
- Send update: Teams' event page (Outlook's form, button "Send") sends service.svc?action=UpdateCalendarEvent from the hosted calendar's worker (captured: TimeZoneContext header, EventId, ItemChange with only the changed SetItemFields, EventScope 0, TargetAudience 0, full attendee lists plus Added/Removed lists when attendees change). OST now sends the same for events without a Teams meeting (send_event_update); Teams meetings keep the middle tier's update.

- Verified live on linuxlt (ost-calQ, profile spatest): --theme=highContrast --cal-test --cal-date=2026-11-23 pixels match Teams (busy #8A8300 composite, free/ended #454200, ended text #BEBEBE, canceled edge #8A8300, today circle and border #FFF200, card top #FFF200 with #5C5C5C edge and lines, hour lines #5C5C5C, all-day tint #1A1900 vs Teams #1A1800); light Month shows the Away crosshatch, Working elsewhere dots and "Filter applied" as Teams.
- Send update: --cal-edit renamed "OST TEST calQ update 23" (OST Test 2 and 3 invited, not a Teams meeting) to "... 24": action update ok; OST Test 2's calendar has "OST TEST calQ update 24" (modified 00:42:18Z) and its inbox the update mail; OST Test 3's copy updated too.
- Test events: all 8 deleted from ost-test1 (Graph DELETE, none left). OST Test 2 and 3 keep "Canceled: OST TEST calQ update 24" and the invitation/update/cancellation mails (read-only access there).
- Tests: lib 939 passed, desktop 37 passed. Commit 5a968cbd.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Calendar high contrast now matches Teams, the show-as bars draw Away and Working elsewhere as Teams does, and Send update works for events that aren't Teams meetings.

What Teams does (measured on winpc 2026-11-23):
- High contrast: the hosted calendar uses Teams' "contrast" palette (themePrimary #FFF200 on #000) through the same tile model as dark: busy #999100, free/tentative/elsewhere/ended #4D4900 at 90 %, grey text by contrast, #FFF200 bars, dates, now line, today and card edge; lines #5C5C5C.
- Filter: Teams shows "Filter applied" for ost-test1 too. Its saved calendar_filters is [["Reservations",["Desk"]]] (Teams unchecks Desk once per device); OST already matched, so no code change.
- Send update on a plain event: Outlook's UpdateCalendarEvent with only the changed fields and the attendee adds/removes.

Changes:
- CalendarView.qml: HC calendar colour #FFF200 and HC removed from the tile special cases (fill, text, bar, canceled edge, busy-day tint); HC lines, dashes, card edge/lines, links, selected ring, mini month; dates, today bar, now line, Month today and card top edge in the calendar colour; Away bar (freeBusyAwayColor, crosshatched) and Working elsewhere bar (dots); card Edit/Delete icon colours.
- src/api/calendar.rs: send_event_update + update_event_request (UpdateCalendarEvent), with a unit test; desktop/src/backend.rs uses it for events without a join link or channel. MeetingForm sends bodyChanged so the body is sent only when edited.
- docs/spec/calendar.md: the request, the HC palette, the bars and Teams' filter rule.

Tests: lib 939 passed, desktop 37 passed; live HC captures and a live Send update checked on OST Test 2.

Open: Teams' event page button reads "Send" where OST's form says "Send update"; a recurrence change on a plain event isn't sent through Outlook yet; OST's card for your own meeting lacks Teams' "You're the organizer. / X didn't respond." row.
<!-- SECTION:FINAL_SUMMARY:END -->
