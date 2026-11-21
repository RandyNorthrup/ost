---
id: TASK-0237
title: >-
  Manage your apps: SharePoint Pages, Forms and Lists rows and Recently used
  order as Teams
status: In Progress
assignee: []
created_date: '2026-11-20T18:48:00Z'
updated_date: '2026-11-21T01:56:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Manage your apps lists 27 apps for ost-test1; OST lists 24. Teams also shows SharePoint Pages, Forms and Lists, which none of the personal, shared or team entitlements return, and its Recently used order differs from the usage service's order. Found in TASK-0077's live check.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manage your apps lists the same apps as Teams for ost-test1, including SharePoint Pages, Forms and Lists
- [ ] #2 Recently used sorts apps in Teams' order
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 source of the missing rows: Teams' teamInstalledAppsManager asks the same aggregatedEntitlements POST with your teams' threads as the body; the answer's teamsEntitlements {thread: [{id, state}]} (with definitions) has OST Test Team's Installed apps SharePoint Pages (0ae35b36), Forms for Microsoft Teams (81fef3a6), Lists (26bc2873) and the SharePoint tab app (2a527703). `GET {mt}/beta/chats/{team}/apps/entitlements` (what OST used) only returns the tenant's permanent apps. manage_apps::installed now uses it (team_apps_from + test).
- Order: Teams sorts by your apps usage (`beta/users/apps/usage` apps), the rest in insertion order: shared apps (Teams' IndexedDB order = by app id: Surveys, Excel (Agent), Word (Agent), Planner Agent, PowerPoint (Agent), Analyst, Researcher), then personal, then team apps. The winpc list was taken before Workflows was used again (usage now starts with Workflows), so Workflows' place differs only by that newer use.
- Live (linuxlt, ost-test1, --manage-apps-test): 27 rows incl. SharePoint Pages, Forms for Microsoft Teams, Lists; Teams on winpc lists 26 — OST also shows the personal SharePoint (Viva Connections, d2c6f111) that Teams leaves out (rule not found yet), and lists the shared agents in the service's order.

- 2026-11-20 merged: team apps via the entitlements request with your teams' thread ids brings in SharePoint Pages, Forms and Lists; shared apps in id order. OST lists 27 rows to Teams' 26: Teams leaves out the personal SharePoint / Viva Connections app (d2c6f111), rule not found yet.

- 2026-11-20 recheck: Teams' Manage your apps on winpc (Recently used) starts SharePoint, Workflows, Whiteboard, Planner, Praise, Polly, Power BI, Polls, OneNote, Avatars, and OST's (--manage-apps-test, linuxlt default) starts with exactly the same ten, so Recently used matches as far as Teams' list was read. That top SharePoint is the personal Viva Connections app d2c6f111 (Installed, isFullScreen, not core), so Teams does list it: the earlier 'Teams leaves d2c6f111 out' note was wrong. OST also lists a second 'SharePoint' row further down (the team SharePoint app); whether Teams lists that one too, and the order after Avatars, still need a full Teams list (the winpc slot ended before the whole list was read).
<!-- SECTION:NOTES:END -->
