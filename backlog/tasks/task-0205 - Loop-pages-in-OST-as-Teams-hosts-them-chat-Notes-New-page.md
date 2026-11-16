---
id: TASK-0205
title: Loop pages in OST as Teams hosts them (chat Notes, New page)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T17:30:00Z'
updated_date: '2026-11-16T20:42:00Z'
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
- [x] #1 A chat's Notes tab shows and edits its Loop page as in Teams
- [x] #2 A channel's New page creates a Loop page tab and shows it as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (e797af6, merged as 6241ee3); spec docs/spec/loop-host.md.
- Loop's page container runs in a same-origin srcdoc frame with Teams' origin (ODSP driver and container from res.cdn.office.net), driven by Fluid's container loader 2.118.1 (vendored in desktop/vendor/fluid-loader, MIT; desktop/THIRD-PARTY-NOTICES.md) with Teams' host services; tokens for SharePoint, the push channel, AugLoop, Graph and Substrate from OST's sign-in, in memory only.
- Verified: OST group test's Notes page shows, takes typing, saves and reloads; New page in OST test channel makes "Loop paragraph" and the tab as Teams writes it; Teams opened an OST-made page. Re-checked Notes on the merged build. Test pages and text removed.
- Leftovers: TASK-0207.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Loop pages work in OST as Teams hosts them: a chat's Notes tab and a channel's New page / Page tabs.

- LoopPage.qml + loop_host.js (Teams' host code re-implemented from the trace) + loop_bridge.js (isolated world); api::loop_page issues the five resource tokens, never logged.
- ChatNotesTab shows the page; New page is enabled in the "+" menu, the narrow tab dropdown and the Existing page dialog; all Page tabs (and Open tab in new window) use the same host with Teams' 50 px header.
- Fluid Framework loader vendored (MIT) with third-party notices.

Tests: unit test against the captured tab property; --loop-test harness live. Follow-up TASK-0207.
<!-- SECTION:FINAL_SUMMARY:END -->
