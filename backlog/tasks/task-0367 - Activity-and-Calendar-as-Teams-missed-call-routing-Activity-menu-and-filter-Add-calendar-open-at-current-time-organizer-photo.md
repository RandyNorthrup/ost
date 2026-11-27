---
id: TASK-0367
title: >-
  Activity and Calendar as Teams: missed-call routing, Activity menu and filter,
  Add calendar, open at current time, organizer photo
status: Done
assignee:
  - '@t367'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T23:35:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-11: Missed-call activity opens the chat instead of Calls ▸ History; fixed to match Teams desktop, checked side by side
- [x] #2 A-12: Activity "···" menu: only "Mark all as read", no shortcut, no "Notification settings"; fixed to match Teams desktop, checked side by side
- [x] #3 A-13: Activity filter box: placeholder and placement differ; fixed to match Teams desktop, checked side by side
- [x] #4 A-14: Calendar navigation pane: no "Add calendar", and the mini month can't be collapsed; fixed to match Teams desktop, checked side by side
- [x] #5 A-15: Calendar opens at 8 AM instead of scrolling to the current time; fixed to match Teams desktop, checked side by side
- [x] #6 A-22: Event peek card: organizer shown as initials instead of their photo; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Research in Teams (web as ost-test1 in a private headless Chrome on linuxlt, CDP; the same app new Teams desktop runs; checked against desktop on testpc/winpc at the end):
- A-11: activity navigation target calls -> callsMain.contactList with defaultFilter MissedCalls / Voicemail; Calls shown beside the feed without the dial pane.
- A-12: generalMenuConfig: Mark all as read (glasses, Shift+Esc = MarkAllAsReadInActivity, no confirm), Notification settings (gear).
- A-13: filter box over the pills (16 in, 72 down, 32 tall, shadow 2, no icon), placeholder "Filter by name or group name", clear button, marks on colorPaletteMarigoldBorder1 at regular weight; tooltips Show/Close filter text box (Ctrl+Shift+F).
- A-14: hosted calendar pane: Date selector chevron collapses the month (session), bottom chevron 1/2 months (calendar_minimonthcount roaming), Add calendar routes Outlook to hosted/calendar/addcalendar (8 sections, all Outlook service calls captured), groups from GetCalendarFoldersV2 with tri-state checkboxes; people calendars from free/busy.
- A-15: useScrollToWorkingHours: floor((now - 10 min)/1440 * height) when today shown, else first working day start (mailboxSettings.workingHours), 9 AM default; on open, range change, Today.
- A-22: organizer photo by mail (Graph user lookup -> profile picture).
Then implement (Rust: calendar groups, free/busy, prefs, mini-month setting, photo by mail; QML: ActivityView, CallsView, CalendarView pane, Main wiring), live-check on linuxlt with --activity-calendar-test, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research: Teams web (ost-test1, private headless Chrome on linuxlt over CDP) for flows and network capture; Teams desktop on winpc (ost-test1, CDP) for the side-by-side: Activity menu (Mark all as read Shift+Esc, Notification settings, right-aligned under ···), filter box (16 in, 72 down, over the pills, "Filter by name or group name"), missed call -> Calls with History on Missed, calendar pane (desktop content 234 wide: Date selector 16, month 54, arrows 164/192, days from 24, toggle row at 101), scroll formula (desktop scrollTop 1144 at 14:28 = floor((868-10)/1440*1921)).
Live on linuxlt (OST profile t367 = ost-test1, harness --activity-calendar-test): menu items and placement; filter "test 3" 8 of 76 with marks; missed call shows Calls beside Activity, filter missed, no chat; calendar opens at now-10 min (contentY 1122 at 14:12, 1162 at 14:42) and next week at 8:00-10 min (626, same as Teams); collapsed / two months / Show all with Outlook groups (My calendars, Team: OST Test 2, Other, People's, Groups); peek shows OST Test 2's photo; Add calendar opens Outlook's own page, Create blank calendar and Add from directory (OST Test 3) from OST came in ticked in the right groups, OST Test 3's free/busy loaded (free_busy events); test calendars removed afterwards (ost-test1 back to Calendar, United States holidays, Birthdays).
Not pressed live: Shift+Esc / Mark all as read (would mark ost-test1's feed read; same action as before), Notification settings (launchSettings("notifications") as the bell's).
Side finding (not changed): OST's Groups section lists all unified groups (3); Teams lists only OST Test Team.

PR #66 opened (branch task-0367-activity-calendar).

CI on PR #66: all green (Build and test, Clippy, Format, release-flag check, CodeQL). Codex: first review's three P2 findings fixed in 947d017a (Calls from an activity close a name search; My calendars and Calendar always listed; no event page for free/busy) and replied on each thread; the re-review of 4c12cfa3 was requested but Codex answered "usage limits reached", so it has not re-reviewed yet.
Rebased on main after PR #54 (Calls history) merged; re-checked live: a missed call shows Calls with Teams' rows (OST TEST 348 invite B ...), Missed filter, 27 of 184.
Cleanup: Teams web headless Chrome and its profile on linuxlt removed, tunnels closed, ost_t367 pactl modules unloaded, ~/ost-build-t367 removed; test calendars on ost-test1 removed (Calendar, United States holidays, Birthdays left).

Removed the throwaway OST profile t367 on linuxlt (as TASK-0368 did): profiles/t367 config, keyring item ost / teams-tokens:t367, QtWebEngine storage and cache (ost-apps-t367), ost-desktop-t367.log and temp logs, and its accounts.json entry (the other six accounts untouched).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Activity and Calendar now work as Teams desktop (PR #66).
- Missed call / voicemail activity opens Calls beside the feed with History on Missed / Voicemail (Teams' calls navigation target, defaultFilter); also from the Activity window.
- Activity ··· menu: Mark all as read (glasses, Shift+Esc, also bound in Activity) and Notification settings; placed under the button's end.
- Activity filter: Teams' box over the pills ("Filter by name or group name", clear button, focus line), filled brand toggle, matches every line with Teams' marks; Ctrl+Shift+F toggles it in Activity.
- Calendar pane rebuilt on Teams desktop's geometry: Date selector collapse, one/two months (calendar_minimonthcount roaming), Add calendar (Outlook's own hosted page, new calendars come in ticked), Outlook's groups (GetCalendarFoldersV2) with tri-state checkboxes; people's calendars from Graph getSchedule free/busy.
- Grid opens at Teams' place: now - 10 min when today shows, else the first working day's start (mailboxSettings.workingHours), on open / date change / Today.
- Peek card shows the organizer's photo (mail: photo ids via Graph user lookup).
Tests: unit tests for calendar groups, free/busy parsing, mail photo ids; live checks on linuxlt against Teams web and Teams desktop (winpc) side by side.
Not verified live: Shift+Esc mark-all (would clear ost-test1's feed), voicemail routing (no voicemail activity). Side finding: OST lists 3 unified groups under Groups, Teams 1.
<!-- SECTION:FINAL_SUMMARY:END -->
