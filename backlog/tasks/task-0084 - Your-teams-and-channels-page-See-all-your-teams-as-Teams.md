---
id: TASK-0084
title: Your teams and channels page (See all your teams) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T20:47:00Z'
updated_date: '2026-11-10T04:28:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The chat list's "See all your teams" opens Teams' Your teams and channels page (Teams, Pending invites, Analytics; filters All / Teams you own / more, Sort, Search teams; team rows with privacy, people, channels, description, a hidden-team eye and the role; each team's ··· and its channels with Show/Hide). In OST the link does nothing, and a team whose channels are all hidden has no way back into the list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 See all your teams opens Teams' page in the conversation's place with its tabs, filters, sort and search, measured against Teams
- [x] #2 Verified side by side with Teams on winpc
- [x] #3 Team rows show Teams' facts, the hidden-team mark and the team menu, and open Manage team, where hidden channels can be shown again (Teams' rows don't expand)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Your teams and channels page (YourTeams.qml, TeamsAnalyticsTable.qml): header, Teams tab (pills, 3 more, sort, search, rows with people/channels/description, hidden mark, archived icon, hover ···/team menu), Pending invites (provisioning users/me/invitations; empty state), Analytics (mt analytics/me/teams summary-timeseries; sparkline). The chat list's See all your teams opens it and shows as chosen; Manage team ▸ Analytics across teams opens its Analytics tab.
- Team list gained role, people (membershipSummary), team type and picture ETag; a changed ETag refetches the cached team picture (the stale OST Test Team picture).
- Verified side by side with Teams (hid all channels and archived OST Test Team to compare, then restored both). Spec §5.6.9.
- The Create team button's flows (Create a team, More create team options, Join a team) are TASK-0086.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Adds Teams' Your teams and channels page (the chat list's "See all your teams").

Changes:
- YourTeams.qml: header with Teams / Pending invites / Analytics and the Create team split button; Teams tab with Teams' filter pills (All, Teams you own, 3 more), sort (A-Z, Z-A, Team type, Membership Type, Visibility Type), search, team rows (people, channels, description, hidden mark, archived icon, hover ··· with the team menu; a row opens Manage team) and the no-match state; Pending invites from the provisioning service with Teams' empty state.
- TeamsAnalyticsTable.qml: analytics across your teams (mt analytics/me/teams summary-timeseries) with the period dropdown, dates, table and sparkline.
- Team list: role, people (membershipSummary), team type, picture ETag; a changed ETag refetches the team picture.
- Manage team ▸ Analytics across teams opens the Analytics tab; See all your teams shows as chosen.

Tests:
- cargo test people_role_and_type, cross_team_analytics_read_as_teams, invitations_read_as_teams
- --your-teams-test harness on linuxlt, compared with Teams on winpc (filters checked with OST Test Team's channels hidden and the team archived, both restored).

Follow-up: the Create team button's flows are TASK-0086.
<!-- SECTION:FINAL_SUMMARY:END -->
