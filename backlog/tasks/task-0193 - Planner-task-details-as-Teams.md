---
id: TASK-0193
title: Planner task details as Teams
status: Done
assignee: []
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T18:59:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's Planner lists, adds, completes and deletes tasks in Grid and Board; Teams also edits a task's details and has Schedule and Charts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A task opens Teams' details (notes, checklist, dates, priority, progress, assignees, labels, bucket) and edits save
- [x] #2 Schedule and Charts views as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20: Teams desktop's Planner is the app's personal page (com.microsoft.teamspace.tab.planner staticTab mytasks, tasks.teams.microsoft.com PlannerFrame, isFullScreen, NAA client 75efb5bc) in its cacheable-iframe; so OST hosts it the same way (TeamsJS host) instead of its native Planner view.

- 2026-11-20 done in OST (worktree agent-a1c49f721b8083768): the app bar's Planner is Teams' personal page in OST's host (Main.qml hostedApps; native PlannerView, api::planner and --planner-test removed). Live on linuxlt (ost-test1, --embedded-apps-test=planner, driven over QTWEBENGINE_REMOTE_DEBUGGING): initialize/appLoaded/success, My tasks as in Teams; made "OST TEST 193 plan" (basic, personal), added "OST TEST 193 task", opened its details (status, priority, dates, repeat, bucket, checklist, notes, task chat), set Important and a checklist item: Graph shows priority 3 and the checklist item; Calendar (Teams' Schedule) and Charts views drawn; plan deleted afterwards (Graph: no plans).

- 2026-11-20 merged as 2c746e0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Planner is hosted as Teams hosts it (its own web app in the TeamsJS host); the native Planner view and api::planner were removed. Verified live: created OST TEST 193 plan and a task, opened details, set Important and added a checklist item (confirmed through the Planner API), Calendar (Schedule) and Charts draw; plan deleted.
<!-- SECTION:FINAL_SUMMARY:END -->
