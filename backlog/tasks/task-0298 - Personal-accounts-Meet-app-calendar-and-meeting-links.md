---
id: TASK-0298
title: 'Personal accounts: Meet app, calendar and meeting links'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T01:04:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0293
  - TASK-0297
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Meet app creates meeting links, schedules meetings, joins with an ID and lists meeting links, scheduled meetings and recent calls. The Calendar has Meet now, New meeting and Join with an ID. Personal meeting links are teams.live.com/meet/... links.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Meet app works as in Teams desktop for a personal account
- [ ] #2 The Calendar shows what Teams shows for a personal account (Outlook.com events or Teams meetings, as verified) with Meet now and New meeting
- [ ] #3 teams.live.com/meet links open in OST, from any account
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- TASK-0369 (2026-11-27): OST now takes teams.live.com links (https://teams.live.com/meet/<ID>?p=…, teams.live.com/l/meetup-join/…, and msteams: links with fqdn=teams.live.com) from the command line, the msteams:/web+msteams: handler and messages, read as TeamsLink::PersonalMeeting (desktop/src/teams_link.rs). Until personal accounts can join, Main.qml openTeamsLink shows "OST can't join Teams (free) meetings yet." with Open in browser. AC #3 here: route PersonalMeeting to the personal account's profile (its instance socket, as open_in_account does) and join it there.

Built so far: OST takes teams.live.com/meet, meetup-join and fqdn=teams.live.com msteams: links (TASK-0369, PR #57; desktop/src/teams_link.rs TeamsLink::PersonalMeeting) but only offers Open in browser (Main.qml); routing them to the personal account and joining are left.
<!-- SECTION:NOTES:END -->
