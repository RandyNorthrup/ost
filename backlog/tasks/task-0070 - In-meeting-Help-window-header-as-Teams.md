---
id: TASK-0070
title: In-meeting Help window header as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T07:21:00Z'
updated_date: '2026-11-09T08:28:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
More ▸ Help opens Teams' Help app on its meetings page in a window of its own. OST's window uses its web-app header (Reload, Open in browser); Teams shows the Help app's tile and a … menu there (seen on winpc, 2026-11-09).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Help window's header shows what Teams' does (app tile, title, … menu with Teams' items), measured on winpc
- [x] #2 The … menu's Reload app reloads the app as Teams'; About and Share app follow in TASK-0072
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc: Help window = child-window title row (#EBEBEB, title, Settings and more: Pin window on top Ctrl+Shift+T, Zoom, Report a problem) + entity-header (app tile from the app definition, name 18/25.71 bold, More Help actions: Reload app, divider, About, Share app).
- About is Teams' full app-details dialog and Share app its Share form: both are features of their own, moved to TASK-0072 (with this task's AC#2 reworded to Reload app).
- Built: ChildWindowTitleBar.qml (also used by the captions pop-out, which gains Settings and more), WebApp appId mode (Teams' entity header, tile via the app definition API), Help window pin on top. Zoom: tracked in docs/parity (main window too); Report a problem: Microsoft feedback, not sent by OST.
- Harness --join-test gained --join-url=<link> (the test meeting left the calendar's loaded week); --join-help verifies the window, menus and pin.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The meeting Help window now looks and acts like Teams'.

Changes:
- ChildWindowTitleBar.qml: Teams' child-window title row (chrome colour, title, Settings and more with Pin window on top / Unpin window, Ctrl+Shift+T). Used by the Help window and the captions pop-out.
- WebApp: with an app id, Teams' app header: the app's round tile (from its app definition), its name, and More <app> actions with Reload app.
- Help window pins on top like Teams'.
- Spec updated; TASK-0072 tracks About (app details) and Share app.
- Test harness: --join-url=<link> to join the test meeting directly; --join-help.

Tests: live --join-help and --join-captions-popout runs on linuxlt (screens compared with winpc).
<!-- SECTION:FINAL_SUMMARY:END -->
