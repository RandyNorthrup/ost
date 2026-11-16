---
id: TASK-0205
title: Loop pages in OST as Teams hosts them (chat Notes, New page)
status: To Do
assignee: []
created_date: '2026-11-16T17:30:00Z'
labels:
  - desktop
dependencies:
  - TASK-0201
  - TASK-0198
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams shows Loop pages (a chat's Notes tab, a channel's New page tab) with Loop's page container: a same-origin srcdoc frame with Teams' origin loaded from res.cdn.office.net with its ODSP driver, driven by Fluid's container loader bundled in Teams, with Loop's host services passed through IFluidDependencySynthesizer, and Teams' web-client tokens for {tenant}.sharepoint.com and pushchannel.1drv.ms (measured 2026-11-16, docs/spec/chat-tabs.md). OST would need the open-source Fluid loader and Loop's host services; it shows "OST can't show these notes yet" and New page is disabled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A chat's Notes tab shows and edits its Loop page as in Teams
- [ ] #2 A channel's New page creates a Loop page tab and shows it as in Teams
<!-- AC:END -->
