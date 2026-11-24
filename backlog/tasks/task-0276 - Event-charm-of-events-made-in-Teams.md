---
id: TASK-0276
title: Event charm of events made in Teams
status: Done
assignee: []
created_date: '2026-11-24T10:07:00Z'
updated_date: '2026-11-24T13:24:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0271: events made in Teams' New event form (OST TEST frmX M1, S1) show the Exam charm on Teams' event page and card, but OST's calendar data has no charm for them (event.charm empty), so OST's page shows the empty charm glyph.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST reads the charm of events made in Teams as Teams shows it (card and event page)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-24 (frmY): Teams' New event form is Outlook's: it picks the charm from the title as you type (each word in Outlook's charm catalog, ows/v1.0/CalendarIcons: "test" → 57 Exam) and creates the event with CharmId 57 (captured: CreateCalendarEvent). Outlook's GetCalendarView answers it as `CharmId` (its `Charm` stays "None"), which OST didn't read.
- Fix: merge_outlook_items reads CharmId (then Charm); Outlook's form read (GetCalendarEvent) gives it too.
- Verified live: "OST TEST frmY T1" made in Teams' New event form on winpc shows the Exam charm on OST's card (before the title) and event page (the charm button), as Teams shows it; Graph-made events with "TEST" in the title have no charm in Teams and none in OST.

- Commit d74e188d. Tests: lib 957 (merge test for CharmId), desktop 37. Test event deleted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Events made in Teams' New event form now show their charm in OST, as Teams does.

Teams' New event form is Outlook's: it picks a charm from the title (Outlook's charm catalog keywords, e.g. "test" → 57 Exam) and creates the event with CharmId; Outlook's GetCalendarView answers it as CharmId with Charm "None". merge_outlook_items now reads CharmId first (then Charm), so the card and the event page show the Exam charm.

Tests: live as ost-test1 with an event made in Teams on winpc (card and page show Exam; Graph-made events stay without a charm, as in Teams); unit test for CharmId/Charm.
<!-- SECTION:FINAL_SUMMARY:END -->
