---
id: TASK-0375
title: Calendar pane Groups list as Teams
status: Done
assignee:
  - '@t378'
created_date: '2026-11-27T23:29:00Z'
updated_date: '2026-11-28T01:49:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0367 (PR #66): OST's calendar pane lists three Microsoft 365 groups under Groups for ost-test1, while Teams desktop lists only OST Test Team. Find Teams' rule (which group calendars it shows) and match it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The calendar pane's Groups section lists the same groups as Teams desktop for the same account, following Teams' documented rule
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find which call Teams' hosted calendar uses for Groups (TASK-0367 capture, HostedCalendarFunctionalBoot on winpc).
2. Use Outlook GetUserUnifiedGroups the same way in src/api/calendar.rs; Graph fallback without groups hidden from Outlook.
3. Unit test with the captured answer; live check with OST's own call for ost-test1.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams' rule: the hosted calendar (owa.HostedCalendarFunctionalBoot, read on winpc over CDP) builds Groups from Outlook's GetUserUnifiedGroups (RequestedGroupsSets FilterType 1 then 2, SortType 4, Descending), every set in order, each group with SmtpAddress + DisplayName + MailboxGuid. The TASK-0367 capture of the same request answered only OST Test Team.
- Graph for ost-test1: three unified groups: Secure Coast Network Solutions (Team, hideFromOutlookClients true), OST Test Team, OST Test Community (Viva Engage community, not hidden; Outlook still leaves it out).
- Teams desktop on testpc1 (ost-test1), Calendar > Show navigation pane > Show all: Groups lists only OST Test Team (UIA dump); put back to Show selected and Chat afterwards.
- OST: calendars() now takes Groups from GetUserUnifiedGroups via owa_action (browser sign-in); without it, Graph memberOf unified groups minus hideFromOutlookClients (per-group GET).

- Live, OST's own GetUserUnifiedGroups for ost-test1 (owa_action example on linuxlt): FilterType 1 [], FilterType 2 [OST Test Team].
- Live, OST on linuxlt (default profile = ost-test1, --activity-calendar-test --t367-only=calendar): pane groups My calendars [Calendar, United States holidays, Birthdays], Team: OST Test 2 [OST Test 2], Groups [OST Test Team], the same sections and entries as Teams desktop on testpc1.
- Unit tests (testpc1 WSL): groups_are_outlooks_unified_groups_as_teams_lists_them, calendars_sit_in_outlooks_groups_as_teams_shows_them pass.
- Not checked live: the Graph fallback (no browser sign-in), and a favourite group (ost-test1 has none).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The calendar pane's Groups section now lists the groups Teams desktop lists (for ost-test1: only OST Test Team, where OST listed three).

Cause: OST took every unified group from Graph /me/memberOf. Teams' hosted calendar (owa.HostedCalendarFunctionalBoot) takes Groups from Outlook's GetUserUnifiedGroups (favourites then the rest, SortType 4, descending), keeping each group with a mail address, name and mailbox. Outlook leaves out Secure Coast Network Solutions (hideFromOutlookClients) and OST Test Community (a Viva Engage community).

Fix (src/api/calendar.rs): group_calendars() sends the same GetUserUnifiedGroups request through owa_action and builds the Groups entries from its sets in order (keyed by the directory id, as OST reads group events from Graph). Without a browser sign-in it falls back to Graph's unified groups minus those hidden from Outlook clients.

Tests: unit test of the request and of the answer's parsing (order, de-duplication, a group without a mailbox left out).

Live: OST on linuxlt (ost-test1) and Teams desktop on testpc1 (ost-test1) both list Groups: OST Test Team. Not live: the Graph fallback path.
<!-- SECTION:FINAL_SUMMARY:END -->
