# Teams' calendar — spec (TASK-0050)

Measured in Teams on the web as ost-test1 on 2026-11-17, inside OST's own
web profile on linuxlt (1852×988 viewport, 1x). Teams' calendar is Outlook
on the web's calendar hosted in an iframe
(`outlook.office.com/hosted/calendar/…`); its scheduling form and event
page for Teams meetings ("calv2") are Teams' own. The same app runs in
Teams desktop.

## Requests

| What | Request |
| --- | --- |
| Week data | Outlook's `outlookgatewayb2/graphql` and `service.svc?action=GetCalendarView`; OST reads Graph `/me/calendarView` with `Prefer: IdType="ImmutableId"` (the ids Outlook uses). |
| RSVP (card, event page, "RSVP with note") | `POST outlook.office.com/owa/service.svc?action=RespondToCalendarEvent&app=Calendar`, empty body; the JSON in the `x-owa-urlpostdata` header: `RespondToCalendarEventJsonRequest` with `EventId` (the occurrence, or the series), `Response` Accept/Decline/Tentative, `SendResponse` ("Email organizer"), `Notes` `<div>note</div>` (HTML), `Attendance` 0, `Mode` 0; headers `action`, `x-req-source: Calendar`, `prefer: IdType="ImmutableId", exchange.behavior="IncludeThirdPartyOnlineMeetingProviders"`. |
| Form opens | `PUT {mt}/v2.0/me/calendars/schedules` (free/busy, "AttendeeAvailabilityOnly"; answers each person's events and the organizer's time zone, e.g. `PacificSt`), `POST {mt}/beta/me/calendarEvents/privateMeeting/schedulingService/create` `{"isStreamEnabled":false,"meetingType":"Scheduled"}` (the meeting's thread, links, dial-in). |
| Send / Save | `POST {mt}/v2.0/me/calendars/default/events?isOnlineMeeting=true&shouldDecryptData=true` with `{calendarEvent, schedulingServiceEvent}`; the event: attendees (organizer first, `role` Admin, `type` Organizer/Required/Optional), `bodyContent`, `startTime`/`endTime` with offset, `eventTimeZone` (PacificSt), `eventType` Single/RecurringMaster, `eventRecurrencePattern` `{patternType (Daily 1, Weekly 2, Monthly 3, RelativeMonthly 4, Yearly 5…), daily/weekly/monthly/yearly: {interval, daysOfTheWeek, dayOfMonth…}}`, `eventRecurrenceRange` `{startDate, endDate}`, `isAppointment` (no attendees), `location`, `showAs`, `reminderMinutesBeforeStart` 15, `skypeTeamsData`. Without the scheduling event the middle tier answers 400 "Scheduling service event cannot be null for online meeting". |
| Channel meeting | `POST {mt}/v2.0/groups/smtp:<team mailbox>/calendars/default/events?isOnlineMeeting=true&shouldDecryptData=false`, the event alone, the team's mailbox as a Required attendee, `mailboxAddress`, `skypeTeamsData` `{"cid":"19:…@thread.tacv2","uid":"8:orgid:…","type":0}`; the service posts the meeting in the channel. |
| Cancel a channel meeting | `PUT {mt}/v2.0/groups/smtp:<mailbox>/calendars/events/<iCalUId>/cancel` `{conversationId, messageId, rootMessageId, cancellationMessageFormat:"The meeting \"{0}\" is cancelled", fetchEventContract:{eventType, eventTimeZone:"UTC", startTime}}`. |
| Meet now | `POST {mt}/beta/me/calendarEvents/privateMeeting/schedulingService/create` `{"meetingType":"MeetNow","isStreamEnabled":false,"subject":"Meeting with OST Test 1","unhideChatThread":true}`, then pre-join on its join link. |
| Join with an ID | `GET {mt}/beta/meetings/identifiers?meetingId=…&passcode=…&link=https://teams.cloud.microsoft/meet/<id>?p=<passcode>` (answers the tenant), then the pre-join's conversation with `meetingData {meetingCode, passcode, meetingUrl}` in place of the thread. |

## Day / Work week / Week

- Toolbar 61 tall: panel toggle, Today, ‹ ›, "November 16–20, 2026 ▾" | "Work week ▾" (Day, Work week, Week, Month; Split view; Time scale 30 minutes; Saved views), Filter, …, "Meet now" + ▾ ("Join with an ID"), "New" + ▾ (Event, Channel meeting, Organization templates: Webinar, Town hall, Virtual appointment, Live Event).
- Day headers 54 tall: date 20 px, day name 12 px, x 13; today brand with a 3 px top bar.
- All-day strip under them, at least 42 tall: bars 18 tall, 21 apart, from 2 px down; radius 4; title 10/600 centred; a multi-day bar spans its days (2.6 in from the first day, 12 short of the last day's right edge).
- Hours 80 px; hour lines #D1D1D1, half-hour lines dashed; labels 11 px at x 10.
- Events: y = start + 2, height = duration − 5; radius 4; fill rgba(199,201,238,.9) busy, rgba(225,225,246,.9) free/tentative/unanswered; 4 px left bar: busy solid brand, tentative or not answered hatched, free white with a brand edge; title 12/600 and the location/organizer 12/400 at x 12, y 4; a 30-minute event shows them on one line. A series' occurrence has the repeat icon (an exception the broken one) bottom right. From five minutes before the start a Teams meeting's tile has "Join".
- Overlaps: lanes, earlier first and then shorter first; lane width (column − 14.6 − 4·(n−1))/n, 2.6 in, 4 apart.
- Column widths in the week holding today: today 30 %, each past day 11 %, the others share the rest, a day needing more for its lanes (n·120.8 + gaps + 14.6) gets it.
- Backgrounds: past days and hours outside 8–17 #FAFAFA; a day under an all-day busy event #EEEFF9.
- An event crossing midnight is drawn in both days; one spanning a full day or starting/ending at midnight goes to the strip (Teams' isMultipleFullDays).

## Month

28 px day names (12 px, x 8); cells 163 tall (the view's height ÷ weeks); date 14 px at 8,6, "Nov 1" on the 1st, today a 22 px brand circle and a brand cell border; events 24 tall, 26 apart from 31.6 down, the cell's width − 8.3: time 12/400 (no ":00") then title 12/600, all-day titles centred; multi-day events span the week's cells; a full cell shows "+N" (#F0F0F0, 12 px #616161), which opens the day.

## Card (peek)

392 wide, radius 4, a brand top edge; title 21/600; the expand button (View event); "Now" (brand 12) for a meeting on now; Join (brand, with ▾) and Chat (white, 1 px #D1D1D1); rows 20 px icons and 14 px #616161 text: time ("Thu 11/19/2026 11:00 AM - 11:30 AM", "Series ↻"), location ("No location added"), who invited you with a 24 px avatar ("OST Test 2 invited you." / "You didn't respond."; a channel meeting: "OST Test Team in the channel OST test channel"), the description; for an invitation: "Email organizer" (checked), "Add a message (optional)" (309×31), Accept (✓ #498205) / Decline (✕ #E81123) / Tentative (? #881798) buttons 32 tall radius 2 border #BDBDBD; for a series each has ▾ with "This event" / "All events in the series"; once answered: the answer and "Change". Your own meeting: Edit and Cancel (Delete for an appointment).

## Event page and form

Teams' calv2 page: header (32 px brand tile, title 18/700, tabs Chat · Details · Scheduling Assistant · …; Join/Send and Close 96×32); a command bar (Cancel meeting, Copy link, Show as ▾ …; an invitation: Accept, Decline, Tentative, RSVP with note); the form (fields 1037 wide from x 74: title, attendees with "+ Optional", Facilitator, date/time pickers with the duration and All day, repeat, Add channel, location with Online meeting, the details editor and its toolbar, Add an agenda) and a right pane (Options; Tracking on an existing meeting). See MeetingForm.qml for every measured size.

- Repeat: Does not repeat, Every weekday (Mon - Fri), Daily, Weekly, Monthly, Yearly, Custom; anything but the first opens "Set recurrence" (Start, Repeat every N unit, weekday circles, End with Remove, a summary such as "Occurs every Monday through Friday until 11/19/2026"), whose summary then labels the dropdown.
- With a channel: Send (not Save), Category disabled, no Facilitator or Online meeting toggle, "OST Test Team > OST test channel" with "Send personal invites".
- "RSVP to <title> with note": 600 wide, "Add a note", a response dropdown (Accept, Decline, Tentative), Confirm / Cancel. Teams on the web offers no Follow; OST sends "Follow" as Outlook's response for it.
- "Cancel meeting?": a cancellation note (optional) and "Cancel meeting".
- "Start a meeting now": Meeting name ("Meeting with <you>"), Start meeting, Get a link to share.
- "Join a meeting with an ID": Meeting ID (ⓘ "You'll find the meeting ID with the other join info near the bottom of the meeting invite."), Meeting passcode, "Join Meeting" (disabled until both are typed).
