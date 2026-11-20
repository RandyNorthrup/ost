---
id: TASK-0237
title: >-
  Manage your apps: SharePoint Pages, Forms and Lists rows and Recently used
  order as Teams
status: To Do
assignee: []
created_date: '2026-11-20T18:48:00Z'
updated_date: '2026-11-20T22:03:00Z'
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
<!-- SECTION:NOTES:END -->
