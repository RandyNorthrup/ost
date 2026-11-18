---
id: TASK-0220
title: >-
  Calendar toolbar extras as Teams: Filter, Time scale, Saved views, Split view,
  propose new time, Event form
status: To Do
assignee: []
created_date: '2026-11-17T16:27:00Z'
updated_date: '2026-11-18T20:08:00Z'
labels:
  - calendar
dependencies: []
references:
  - docs/spec/calendar.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Calendar parts Teams has that OST doesn't yet, found while finishing TASK-0050: the toolbar Filter menu, Time scale, Saved views, Split view, propose a new time, the New ▾ Event form (hosted from Outlook) and the Copilot parts. The Live meetings dialog's avatar row needs the live participant list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The calendar toolbar has Teams' Filter menu (Appointments, Meetings, Poll holds, Reservations, Categories, Show as, Recurrence, In-person) and filters events as Teams does, including the 'Filter applied' state
- [ ] #2 Time scale, Saved views and Split view work as in Teams desktop
- [ ] #3 Propose new time works from an invitation as in Teams, and the organizer sees the proposal
- [ ] #4 New ▾ Event opens Teams' Event form and creates an event as Teams does
- [ ] #5 The Live meetings dialog's avatar row shows everyone in each live call, as Teams
- [ ] #6 The calendar's Copilot entry points are shown as in Teams for a Copilot-licensed user
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-18: Researched Teams desktop's hosted calendar (Outlook on the web's bundles, fetched from the CDN through its runtime's chunk map, and Teams' own bundles for the Live meetings dialog) and measured on winpc. Spec: docs/spec/calendar.md "Toolbar extras (TASK-0220)".
- Filter menu: native, with Teams' V2 rules, its overflow rule (inline from a 1321 px frame, else in More) and "Filter applied". Kept in the global calendar_filters roaming setting (the account scope is refused), with Teams' first-run Reservations > Desk default. Verified live: Appointments off and on again round-trips; Teams on winpc still shows its filter.
- View menu: Day 1-7 days; Split view (disabled with one calendar, as in Teams); Time scale (Outlook options' CalendarSurfaceOptions; 40/30 px slots); Saved views (ows/v1/SaveCalendarView, PUT to save, DELETE) with Teams' dialog and charm picker. Verified: 15 minutes and 3 days set and put back; a saved view created and deleted.
- New > Event hosts Outlook's compose page (hosted/calendar/deeplink/compose, subEntityId {"type":"compose"}) as Teams' Calendar app: getAuthToken gets the hosted calendar's brokered Outlook token (ic3 gets Teams' token), getConfigSetting answers "", and stageView.self.close closes it. Verified: "OST TEST 220 event form" saved from it (Graph shows it), then deleted.
- Propose new time: RespondToCalendarEvent with ProposedStartTime/EndTime. When Outlook answers an empty 204 (seen for test3), Graph's tentativelyAccept/decline with proposedNewTime. The organizer's card shows Teams' "{name} proposed new time", the time and Accept. Verified both ways with OST Test 3; Teams on winpc showed test3's proposal on test1's meeting.
- Live meetings dialog: each live meeting's call is watched without joining (a tagged LiveRoster), up to 3 avatars then +N. Verified with test3 in "OST TEST 220 live".
- Copilot, shown for licenseDetails isCopilot: the calendar's Chat with Copilot button with its suggestions, and Outlook's Copilot pane (hosted/semanticoverview, CalendarSidepane); the card's Add a room with Copilot, Prepare for this meeting and prompts.
- Open:
  - Teams' propose form is Outlook's (with its scheduling assistant); OST's is a simpler native dialog.
  - Suggestions and prompts aren't passed into the Copilot pane.
  - Split view needs more calendars (OST lists only Calendar).
  - More's Share, Print and Calendar settings rows aren't there.
  - Poll holds, desk bookings and hybrid RSVP attendance aren't read, so those filters pass everything.
  - test3's scheduling form sent an empty time zone, so its meeting landed at 2 AM (a TASK-0050 issue).
<!-- SECTION:NOTES:END -->
