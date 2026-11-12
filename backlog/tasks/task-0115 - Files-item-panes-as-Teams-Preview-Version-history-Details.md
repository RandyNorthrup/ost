---
id: TASK-0115
title: 'Files item panes as Teams: Preview, Version history, Details'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-12T06:37:00Z'
updated_date: '2026-11-12T17:48:00Z'
labels:
  - files
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Files menu (OneDrive app, channel Files) has Preview (the file viewer over the window), Version history and Details (the item's side pane). OST's menu (FileActions.qml, docs/spec/file-actions.md) leaves them out until each is drawn natively. Research each on winpc first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Preview opens the file's viewer as Teams does, natively
- [x] #2 Version history lists the file's versions as Teams does, with its actions
- [x] #3 Details opens the item's details pane as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC#2 Version history done (commit after 1ecc39b): SharePoint versions/RestoreByLabel/RecycleByLabel; spec docs/spec/version-history.md; harness --version-history-test [--version-history-live].
- Details research: pane = DetailsPaneContainer 304 wide; thumbnail, Has access, All activity (v2.0 activities with @sharePoint.localizedRelativeTime), comments (GetComments, CommentsDisabled), More details (Type, Modified, Date created, Path, Size). Activity strings dumped (ondemand.resx module 6612).

- AC#3 Details pane done: DetailsPane.qml + item_details.rs; spec docs/spec/details-pane.md; harness --details-test [--details-live]. Bell on fails with OST token (TASK-0122); comment edit/replies (TASK-0121). Narrow list breakpoint (640) not measured.
<!-- SECTION:NOTES:END -->
