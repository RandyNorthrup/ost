---
id: TASK-0381
title: 'Channel meeting pages: Forward, and organizer Edit, as Teams'
status: Done
assignee:
  - '@t381'
created_date: '2026-11-28T04:35:00Z'
updated_date: '2026-11-28T07:53:00Z'
labels:
  - desktop
  - channels
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0374 (PR #74). A meeting opened from a channel's Meetings pane via the team calendar has no Forward button, which Teams shows. And the organizer's Edit opens a read-only page: the existing calendar page doesn't treat the organizer of a channel meeting as organizer, so it shows no edit controls. Also not clicked live yet: the per-meeting Copy link.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A channel meeting opened from the team calendar shows Teams' Forward, and forwarding works with test accounts
- [x] #2 The organizer of a channel meeting gets Teams' editable meeting page from Edit
- [x] #3 Copy link from the Meetings pane's ··· copies the same join link Teams copies (checked live)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams desktop: testpc2 (OST Test 2) channel Meetings pane ··· Copy link (clipboard), the team-calendar page and its Forward meeting dialog; testpc1 (ost-test1, organizer) Edit; Teams' bundles for forwardTeamEvent / updateTeamEvent.
2. Copy link: plain join URL like Teams.
3. Forward: command-bar button and Forward meeting dialog on channel meeting pages; middle-tier forward (group route for team calendar events, me route for your copy).
4. Organizer: mark your channel meetings as yours (SkypeTeamsProperties uid) in the calendar view and the team-calendar page; Teams' organizer bar; Send update through updateTeamEvent.
5. Unit tests, harness --channel-meeting-page-test, live checks with test accounts, undo changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop (testpc2, OST Test 2): the Meetings pane's ··· Copy link puts only the meetup-join URL on the clipboard (formats: text only, no HTML), no toast. The team-calendar page bar: [Accepted ▾ | Add to calendar] | Copy link, → Forward, Show as: Busy (greyed). Forward meeting dialog measured (500 wide, padding 32, Add people 436 x 50, note 34, info line, Forward 84 x 32), suggestions name + (ALIAS).
- Teams desktop (testpc1, ost-test1): Edit on the pane opens the editable page with Cancel meeting | Copy link, Show as greyed, ···; no Category, no Forward.
- Graph: ost-test1's copy of a channel meeting names the team as organizer with isOrganizer false; the meeting's SkypeTeamsProperties uid names ost-test1. calendar_view now expands that property and marks such meetings as yours (organizer you, team kept as group_address, the team dropped from attendees); cancelled copies stay as they are.
- Teams' bundles: forwardTeamEvent = POST {mt}/v2.0/groups/smtp:<team>/calendars/events/<id>/forward?useICalUId=false&isBackedBySubstrateGroup=false {forwardAttendees, messageBodyPrefix}; a private event uses v2.0/me/calendars/events/<id>/forward. updateTeamEvent = PUT {mt}/v2.0/groups/smtp:<team>/calendars/events/<iCalUID>?isOnlineMeeting= {updateMessageFormat "The meeting has been updated", updatedCalendarEvent (the form's loaded event with its changes), fetchEventContract}.
- Live: the update first failed "Offline to Online conversion not supported yet" with a body built from scratch; it now starts from GET {mt}/v2.0/groups/smtp:<team>/calendars/events/iCalUId/<uid>?eventStartDateTime=. One run dropped ost-test1 from the attendees (the middle tier's copy leaves the organizer out) and Exchange cancelled their copy; the organizer now goes first as Teams' form sends it, and a resend restored the copy (same id, not cancelled, same attendees). Rooms (Resource attendees) are kept on updates.
- Compiled QML: a `readonly property var list` read as empty in the Forward suggestions; renamed to `hits` (the form's attendee suggestions too).
- Cleanup: the update re-invited OST Test 2 (listed as accepted since TASK-0374, without a copy); their added copy was deleted twice to leave them as before. The forward to OST Test Room (accepted by the room) was undone by an organizer update without the room.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel meeting pages as Teams desktop: Forward, the organizer's editable page, Copy link.

- Copy link (Meetings pane ···): the plain join URL, no HTML, no toast, as Teams desktop copies it (testpc2 clipboard).
- Forward: on a channel meeting read from its team's calendar, and on a channel meeting invitation, after Copy link; Teams' Forward meeting dialog (people picker with directory suggestions, optional note, "The organizer will receive a notification…", "At least one recipient is needed."). Sent through the middle tier's forwardTeamEvent (team calendar) or forwardCalendarEvent (your copy).
- Organizer: Graph names the team as organizer of a channel meeting; the calendar view now reads the meeting's SkypeTeamsProperties uid and marks yours as yours, so Edit (and the calendar) open the editable page. Its bar is Teams': Cancel meeting | Copy link, Show as greyed, ··· (no Category). Send update goes to the team's calendar (updateTeamEvent) with the event as the service loads it plus the form's changes; you stay on it, rooms stay booked.
- Compiled QML read a `list` property as empty; the suggestion lists use `hits`.

Tests: unit tests for the organizer marking, the forward body and the update merge; --channel-meeting-page-test (harness).
Live (linuxlt, test accounts): Copy link text = join URL; ost-test1 gets the editable page; a title update reached OST Test 3's calendar and was reverted; OST Test 2 forwarded the meeting to OST Test Room from the team calendar (204, the room added and accepted), undone by an organizer update.
Follow-up: TASK-0384 (page fields, RSVP menu, rooms).
<!-- SECTION:FINAL_SUMMARY:END -->
