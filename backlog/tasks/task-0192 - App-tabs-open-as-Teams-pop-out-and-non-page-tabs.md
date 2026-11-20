---
id: TASK-0192
title: App tabs open as Teams (pop-out and non-page tabs)
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
OST's tab window shows only page tabs; other app tabs say they aren't available.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 App tabs open inside OST, popped out or not, as Teams opens them
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 research: the app bar's right-click menu (Open in new window, About, Share app, Pin, Uninstall, Customize app bar; 170 wide) pops a personal app out into a 946 x 593 child window titled with the app's name (Settings and more); a full-screen app (Planner) fills it under the title row; others (Whiteboard) get the entity-header (32 px icon, name 18 bold, ··· "More <app> actions").

- 2026-11-20 built: AppRail right-click menu on hosted apps (Open in new window, About, Share app) → AppWindow.qml (946 x 593, title row with the app's name, the personal page with isMultiWindow); --app-window-test. Teams' Pin, Uninstall and Customize app bar not in that menu yet.

- 2026-11-20 live: --app-window-test=planner: "Planner" window 946 x 593 with the title row, Planner's page signed in (initialize/appLoaded/success, entity mytasks, no header as Teams).

- 2026-11-20 merged as 2c746e0. Pin, Uninstall and Customize app bar moved to TASK-0238.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Hosted apps open as Teams: the app bar's right-click menu has Open in new window, About and Share app; the new window (AppWindow.qml) is 946x593 and titled with the app. Planner verified signed in via --app-window-test=planner. Teams' Word file tab is a regular app tab, already shown. Follow-up TASK-0238 for Pin, Uninstall, Customize app bar.
<!-- SECTION:FINAL_SUMMARY:END -->
