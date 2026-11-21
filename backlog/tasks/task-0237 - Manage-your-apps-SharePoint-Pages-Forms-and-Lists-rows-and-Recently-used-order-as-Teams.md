---
id: TASK-0237
title: >-
  Manage your apps: SharePoint Pages, Forms and Lists rows and Recently used
  order as Teams
status: In Progress
assignee: []
created_date: '2026-11-20T18:48:00Z'
updated_date: '2026-11-21T19:21:00Z'
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
- [x] #1 Manage your apps lists the same apps as Teams for ost-test1, including SharePoint Pages, Forms and Lists
- [x] #2 Recently used sorts apps in Teams' order
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 source of the missing rows: Teams' teamInstalledAppsManager asks the same aggregatedEntitlements POST with your teams' threads as the body; the answer's teamsEntitlements {thread: [{id, state}]} (with definitions) has OST Test Team's Installed apps SharePoint Pages (0ae35b36), Forms for Microsoft Teams (81fef3a6), Lists (26bc2873) and the SharePoint tab app (2a527703). `GET {mt}/beta/chats/{team}/apps/entitlements` (what OST used) only returns the tenant's permanent apps. manage_apps::installed now uses it (team_apps_from + test).
- Order: Teams sorts by your apps usage (`beta/users/apps/usage` apps), the rest in insertion order: shared apps (Teams' IndexedDB order = by app id: Surveys, Excel (Agent), Word (Agent), Planner Agent, PowerPoint (Agent), Analyst, Researcher), then personal, then team apps. The winpc list was taken before Workflows was used again (usage now starts with Workflows), so Workflows' place differs only by that newer use.
- Live (linuxlt, ost-test1, --manage-apps-test): 27 rows incl. SharePoint Pages, Forms for Microsoft Teams, Lists; Teams on winpc lists 26 — OST also shows the personal SharePoint (Viva Connections, d2c6f111) that Teams leaves out (rule not found yet), and lists the shared agents in the service's order.

- 2026-11-20 merged: team apps via the entitlements request with your teams' thread ids brings in SharePoint Pages, Forms and Lists; shared apps in id order. OST lists 27 rows to Teams' 26: Teams leaves out the personal SharePoint / Viva Connections app (d2c6f111), rule not found yet.

- 2026-11-20 recheck: Teams' Manage your apps on winpc (Recently used) starts SharePoint, Workflows, Whiteboard, Planner, Praise, Polly, Power BI, Polls, OneNote, Avatars, and OST's (--manage-apps-test, linuxlt default) starts with exactly the same ten, so Recently used matches as far as Teams' list was read. That top SharePoint is the personal Viva Connections app d2c6f111 (Installed, isFullScreen, not core), so Teams does list it: the earlier 'Teams leaves d2c6f111 out' note was wrong. OST also lists a second 'SharePoint' row further down (the team SharePoint app); whether Teams lists that one too, and the order after Avatars, still need a full Teams list (the winpc slot ended before the whole list was read).

- 2026-11-20 correction after reading Teams' whole list on winpc (27 rows, Recently used): SharePoint, Workflows, Whiteboard, Planner, Praise, Polly, Power BI, Polls, OneNote, Avatars, Surveys, Excel (Agent), Word (Agent), Planner Agent, PowerPoint (Agent), Analyst, Researcher, Facilitator, Updates, Viva Learning, Power Apps, Copilot, Engage, Power BI (MSIT), SharePoint Pages, Forms for Microsoft Teams, Lists. OST lists the same 27 in the same order plus one more 'SharePoint' between Copilot and Engage, which is the personal Viva Connections app d2c6f111 (the top SharePoint is the team SharePoint app 2a527703, placed by usage). So the earlier finding stands and my previous recheck note was wrong: Teams leaves d2c6f111 out. Its definition (Installed, isFullScreen, isFullTrust, a Personal static tab on {teamSiteDomain}, no officeAssetId) shows no flag that explains it, and no ECS list in the 26304 config names it for Manage apps; the rule is still unknown. AC2 (order) matches.

- 2026-11-20 round 3, Teams' code path for the list (26304 worker): installedAppsForUser (j$t) → b$t merges shared (V$t) and personal (H$t) then team apps; H$t keeps userInstalledAppsManager.getInstalledApps entries whose state is Installed / AdminPreInstalled / InstalledAndFavorited (+ PreConsented unless ECS disablePreConsentedAppsInManageApps) as isInstalledPersonally rows; j$t then drops empty ids, the multimodal AI bot (Ws.GK: calling.enableMultiModalAiHideBot / multiModalAiBotId) and Facilitator when enableHideFacilitatorFromManageApps; the UI (chunk 89511) shows rows with teams, chats or isInstalledPersonally. None of these names d2c6f111, so it must drop out in getInstalledAppsInternal → Si.YE(Personal, userEntitlements, definitions, installedDefinitions) (lead: the definitions Teams pairs with the entitlements), not read to the end yet.

- Further: Teams' Si.YE only pairs each entitlement with its definition, and F$t only sorts (usage, else A-Z; updates first), and OST's state filter equals Teams' (x$t/B$t). So by the code d2c6f111 (Installed) would be listed; Teams' own entitlement cache must hold it differently (another state, or not at all) than the aggregatedEntitlements answer OST reads. Next step: read Teams' app entitlement store (IndexedDB) on winpc for d2c6f111's state and compare with OST's request (OST asks ?appbarview=userpinned).

- 2026-11-21 winpc, Teams' own store (IndexedDB Teams:user-installed-apps-manager … user-app-entitlements): every personal entitlement Teams got from its aggregated sync carries isInstalledPersonally: true (Teams' prepareAggregatedAppsForPersistence adds it), but d2c6f111's entry is {state Installed, authorization …} without it, so Teams stored it through another path (not its aggregated sync) and doesn't list it. OST's aggregatedEntitlements answer (?appbarview=userpinned) includes d2c6f111 as Installed. To match: find the request Teams' sync makes (its query parameters) that leaves d2c6f111 out, or the path that adds it without the flag.

- 2026-11-21 (teamsG) winpc recheck by app id (CDP, React props of each row, read-only): Teams' Manage your apps lists 31 rows and DOES include the personal SharePoint / Viva Connections app d2c6f111 (between Copilot and Engage, isInstalledPersonally true) as well as the team SharePoint 2a527703 at the top. The earlier "Teams leaves d2c6f111 out" came from reading the list by name (two rows named SharePoint, and two named Planner: com.microsoft.teamspace.tab.planner and 75f31797, collapsed into one). Teams' stored entitlement for d2c6f111 now carries isInstalledPersonally and its definition 1.0.55 (user-installed-apps-manager IndexedDB, Personal_ring3_6 key). So OST listing d2c6f111 there matches Teams. Teams' rows today: OST TEST 206 channel Agent, SharePoint (2a527703), Workflows, Whiteboard, Planner, Praise, Polly, Power BI, Polls, OneNote, Avatars, Surveys, Excel (Agent), Word (Agent), Planner Agent, Planner (75f31797), PowerPoint (Agent), Analyst, Researcher, Wikipedia Search, Facilitator, Updates, Viva Learning, Power Apps, Copilot, SharePoint (d2c6f111), Engage, Power BI (MSIT), SharePoint Pages, Forms for Microsoft Teams, Lists.

- 2026-11-21 (teamsG) Teams' shared apps are keyed by app id only (Map([...shared, ...personal])), so the shared Planner 75f31797 is a row beside your own Planner. OST's "a shared copy of an Office asset you have shows once" rule (not Teams') was removed. Live (spatest, --manage-apps-test): OST now lists Teams' 31 rows in Teams' order, plus Azure Boards (after Researcher) and "OST TEST channel Agent" (after Facilitator).
- Why those two: Teams' Manage your apps reads its stored personal entitlements, last synced 2026-11-21 04:38Z (IndexedDB Personal_ring3_6, read on winpc), and that copy doesn't have them. Its shared-apps copy (refetched 08:32Z when Manage your apps opened) doesn't have them either. Teams' "Your agents and apps" (a fresh service call) did list Azure Boards at 08:33Z. So the two rows are apps added after Teams' last entitlement sync, and OST shows the service's current state. They weren't confirmed in Teams after a fresh sync (that needs a Teams restart on winpc).

- 2026-11-21 (teamsH) AC1 after a Teams restart on winpc: Teams' stored personal entitlements re-synced (IndexedDB Personal_ring3_6 last update 19:04Z) and now hold Azure Boards 7299542a (Installed), Wikipedia Search 25492237 (Installed) and both "OST TEST channel Agent" apps 24006ec3 / 0dfe1f3c (PreConsented). Teams' Manage your apps, read by app id from each row's React props: 35 rows - 2081505e (OST TEST 206 channel Agent), 2a527703 SharePoint, c3a1996d Workflows, 95de633a Whiteboard, com.microsoft.teamspace.tab.planner, d832a33f Praise, 1542629c Polly, 1c4340de Power BI, 0e3bedea Polls, 0d820ecd OneNote, 96a116ab, 2e49bd44, 331d4605, 4674e5f9, 4aba4be7, 75f31797 Planner, a17b6823, cca447a8, e6d03825, 7299542a Azure Boards, 25492237 Wikipedia Search, 8e55a7b1, 24006ec3 and 0dfe1f3c OST TEST channel Agent, a59fe11a Custom Streaming, 99e46335, 2e3a628d, a6b63365, 4046041d, d2c6f111 SharePoint, db5e5970, feda49f8, 0ae35b36 SharePoint Pages, 81fef3a6 Forms, 26bc2873 Lists.
- OST (spatest, --manage-apps-test, same minute): the same 35 rows in the same order (OST TEST 206 channel Agent, SharePoint, Workflows, Whiteboard, Planner, Praise, Polly, Power BI, Polls, OneNote, Avatars, Surveys, Excel (Agent), Word (Agent), Planner Agent, Planner, PowerPoint (Agent), Analyst, Researcher, Azure Boards, Wikipedia Search, Facilitator, OST TEST channel Agent x2, Custom Streaming, Updates, Viva Learning, Power Apps, Copilot, SharePoint, Engage, Power BI (MSIT), SharePoint Pages, Forms for Microsoft Teams, Lists). So the two extra rows were Teams' stale copy; no rule left to match. (Custom Streaming is new in both: added and removed again in TASK-0212's town hall test, which left its personal entitlement.)
<!-- SECTION:NOTES:END -->
