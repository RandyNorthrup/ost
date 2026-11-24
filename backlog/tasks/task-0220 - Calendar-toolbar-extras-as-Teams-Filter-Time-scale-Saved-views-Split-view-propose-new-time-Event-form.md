---
id: TASK-0220
title: >-
  Calendar toolbar extras as Teams: Filter, Time scale, Saved views, Split view,
  propose new time, Event form
status: Done
assignee:
  - '@claude'
created_date: '2026-11-17T16:27:00Z'
updated_date: '2026-11-19T00:05:00Z'
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
- [x] #1 The calendar toolbar has Teams' Filter menu (Appointments, Meetings, Poll holds, Reservations, Categories, Show as, Recurrence, In-person) and filters events as Teams does, including the 'Filter applied' state
- [x] #2 Time scale, Saved views and Split view work as in Teams desktop
- [x] #3 Propose new time works from an invitation as in Teams, and the organizer sees the proposal
- [x] #4 New ▾ Event opens Teams' Event form and creates an event as Teams does
- [x] #5 The Live meetings dialog's avatar row shows everyone in each live call, as Teams
- [x] #6 The calendar's Copilot entry points are shown as in Teams for a Copilot-licensed user
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

- First pass merged into desktop/foundation (2026-11-18): build OK, 744 lib tests passed. Follow-up for AC1–AC6 is being verified live.
Follow-ups (2026-11-18, second pass):
- AC1: events now carry Outlook's view of them. GetCalendarView items are matched by immutable id and give IsMeeting, EventPollMetadata Type/VoteType, CalendarEventClassifications DeskBooking, RequestedAttendanceMode and Charm, so Poll holds, Reservations and In-person really filter. The toolbar's "…" is always there: Filter (when it isn't inline), a divider, Share (a submenu of the shareable calendars when there are several), Print, Calendar settings. These click the same command in Outlook's hosted calendar surface, which shows Outlook's own Sharing and permissions, Print and Calendar Settings dialogs (checked live). The layer closes once the dialog has gone. Submenus are placed again once they have laid out (flipped left, lifted up), so they stay in the window; checked live with More ▸ Filter ▸ Meetings.
- AC2: the pane lists My calendars (Graph /me/calendars) and Groups (unified groups), collapsed to the ticked ones, with Show all / Show selected. Ticked calendars add their events, and Split view gives each calendar its own block of days (at least 100 px per day, scrolling sideways, a 56.67 header with the name and close; the hours stay put). Checked live with "OST TEST 221 calendar" made on ost-test1: two blocks; the calendar is deleted again.
- AC3: tiles have a right-click menu: Join, Chat with participants, Copy meeting link; Print; Accept / Decline / Tentative, Propose new time, Forward; Charm (picker), Show as, Categorize, Private; Duplicate event, Save as .ics, Delete. Propose new time hosts Outlook's own propose form with its scheduling grid. The hosted calendar is routed to hosted/calendar/item/<id> with pushState, because a fresh load goes back to the view, and Outlook's own command is clicked. The layer closes when Outlook leaves the event page. The card's own propose link is gone (Teams' card has none). Checked live: OST Test 3 scheduled OST TEST 221 propose at 10:00 PST through the TASK-0050 code, and it now lands at 10:00. With no zone from the mailbox, the middle tier now gets UTC times with eventTimeZone UTC. ost-test1 proposed 11:00 in Outlook's form, Graph shows proposedNewTime 19:00Z, and OST Test 3's card shows "OST Test 1 proposed new time / Thu 11/19/2026 11:00 AM - 11:30 AM / Accept".
- Charm: UpdateItem takes the number (3) and GetCalendarView answers the name ("Plane"); both are mapped to the picker's ids.
- AC4: Outlook's propose form pops itself out with stageView.open (host TeamsModern desktop). app_host handles stageView.open, and OST opens the page in a window of its own; the compose bar's Open in new window does the same (checked live: cal-popout). The form has the Microsoft Teams meeting toggle (off until there's an attendee) and its Copilot entries (reschedule toggle, Add a room with Copilot, the agenda hint).
- AC5: Teams' join bar comes from MeetingStart notifications (services-live-meeting-status-bar). It drops huddles, starts from the lobby, duplicates within 60 s, and events outside 15 min before the start to 5 min after the end. The client must be running when the call starts. Live with two meetings: OST got A's start, and the dialog showed A with O2. B's restart sent ost-test1 no MeetingStart, and the guests stayed in A's lobby, so +N and the two-card dialog are still to be shown.
- AC6: suggestions and card prompts go into the pane with updatePromptInputData {promptText, correlationId, promptTimestamp, isDraft, focusOnLoadTarget} once it's ready, using Outlook's prompt strings. Checked live: "Schedule 1 hour of focus time for me in the next week" ran in the pane, and nothing was booked. With the pane open, "…" holds Go to today, previous, next, the range, the view, Filter, New (split), Share, Print, Calendar settings (measured on winpc), matched live.
- Open: Outlook's Print button in its print dialog made no print request in QtWebEngine (it prints a nested frame). WebApp now turns window.print into a PDF in Downloads, but this path is not reached yet.

- Merged d7dcbd1 (2026-11-18): build OK, 745 lib tests passed. AC2, AC3, AC4 and AC6 verified live. Open: AC1 Print from Outlook's dialog and Instructions ›; AC5 multi-meeting +N and Teams' avatar overlap.
Last three items (2026-11-18):
- Print: Outlook's print dialog writes its preview into a same-origin PrintableIframe and calls that frame's contentWindow.print() (Teams prints it with WebView2). QtWebEngine gave OST no print request for it, so WebApp now injects a print hook into every app frame. The hook catches window.print and print on the child frames reached through contentWindow, and posts the document to the host page (app_host.js, ostPrint). OST loads it in a hidden view, prints it to a PDF in Downloads and opens that. Verified on linuxlt with a PDF only (--cal-print-quiet): "Calendar 2026-11-18 142202.pdf", A4, 1 page, Outlook's work-week preview with the test event. lpstat shows no new jobs. The test PDF is deleted.
- Instructions ›: in the tile menu for a Copilot user, as Outlook's CalendarItemContextMenu has it (calendarInstructions). Create instruction (only when you're not the organizer) opens Copilot's pane with the draft "Always {accept|follow|decline} meeting from {organizer}", or "Automatically delete canceled meetings" / "Help me create calendar instructions". Manage instructions opens Outlook's Calendar settings at Calendar instructions. Verified live: the draft in the pane, unsent, and the settings page. Outlook's command steps now match by visible text, because Fluent tabs keep a hidden copy of their label.
- AC5 live: test2 and test3 each organized a new meeting with ost-test1 (OST TEST 223 live E and F), with the lobby set to Everyone (examples/meeting_lobby) and put back to EveryoneInCompany afterwards. With OST running as ost-test1 before the calls started, OST got both MeetingStarts and showed "Meetings Started: OST TEST 223 live E +1 / View meetings". The Live meetings dialog had E with O2, two guests and +1 (OST Test 2 admitted three guests) and F with O3. Teams on winpc, idle and running, showed no join bar (no MeetingStart reached it), and restarted calls get no MeetingStart at all. So the avatar overlap is taken from Teams' Griffel CSS (griffel-37c74cd32cb2b4d1.css), not measured live: isRosterParticipantAvatar margin 0 -1rem 0 0, html font-size 10px, so a 10 px overlap; chatLiveRosterList padding-right 1rem; +N is an avatar of the same size. OST already matches.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Calendar extras as Teams desktop (Outlook on the web hosted in Teams), checked live against winpc.

- Filter: all eight groups with Teams' menu behaviour, overflow rule and Outlook's calendar_filters cloud setting (shared with Teams, including the first-run Reservations ▸ Desk default). Poll holds, desk bookings and in-person come from Outlook's own event view (unit-tested; no test account has such events). "…" has Filter, Share, Print and Calendar settings opening Outlook's own dialogs; Print from Outlook's preview goes to a PDF.
- View menu, Time scale, Saved views (PUT), calendars and groups list, Split view.
- Tile right-click menu with Outlook's propose form, Print, Forward, Duplicate, .ics, charm, Show as, Categorize, Private and Instructions ›; organizer cards show proposals with Accept. Scheduling sends UTC when the mailbox has no time zone.
- New ▾ Event hosts Outlook's form with Open in new window and its pop-out.
- Live meetings: MeetingStart-driven join bar and dialog, several calls watched at once, up to 3 avatars then +N (verified with two fresh meetings, 4 people in one). The 10 px overlap comes from Teams' CSS: Teams on winpc received no MeetingStart to show its bar.
- Copilot: toolbar button and pane, card prompts, suggestions passed into the pane; "…" takes the toolbar items while the pane is open.
- Harness: --cal-more, --cal-popout, --cal-print-quiet; examples/meeting_lobby.rs, examples/calendar_admin.rs. 748 lib tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
