---
id: TASK-0040
title: Channel tabs behave exactly as Teams desktop (per docs/spec/channel-tabs.md)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T02:35:00Z'
updated_date: '2026-11-07T03:23:00Z'
labels:
  - desktop
  - tabs
dependencies: []
references:
  - docs/spec/channel-tabs.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST's channel tab strip and tab menu were built from screenshots and differ from Teams: wrong item set, hidden instead of disabled moves, wrong move algorithm, Graph instead of the middle tier, missing Page tab. Rebuild them from the researched spec (Teams client code + live client on winpc).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Tab list comes from the middle tier's pinned tabs (as Teams), including the channel Page tab
- [x] #2 Chevron only on the active tab that has a menu; right-click menu on any tab with a menu; item order, visibility and disabled states per tab type exactly as the spec table
- [x] #3 Move left/right use Teams' order algorithm (one tab re-ordered, one PATCH) and are disabled, not hidden, at the ends
- [x] #4 Rename dialog: title, Tab name label, validity icon, empty / 128-char / duplicate errors, Save, X close; saved through the middle tier
- [x] #5 Remove dialog: tab and Page variants, Remove → Removing, failure text; removed through the middle tier
- [ ] #6 Copy link to tab writes Teams' exact deep link (channel or entity form) as rich text with the tab name
- [ ] #7 Open in browser opens the tab's website URL in the system browser
- [ ] #8 Reload tab, Expand tab, Open tab in new window, About this tab and App permissions act on OST's native tab views as Teams' do
- [ ] #9 Verified side by side against Windows Teams on winpc in OST Test Team
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. src/api/tabs.rs: load pinned tabs from the middle tier (v1.0 channels/{thread}/tabs) plus app definitions (beta/users/apps/definitions/{id}, cached); classify each tab (StaticExtension Files, ChannelPage, Website, Extension, OneNote legacy); add Posts.
2. Menu model in Rust: exact We() order + c/m filters (submenu vs right-click), disabled moves; tests from the live ground-truth table.
3. Order: Teams newOrder() algorithm, single UpdatePinnedTabs PATCH; rename via the same PATCH (name); remove via DELETE beta/channels/{thread}/tabs/{id}; probe each on a test tab in OST Test Team first.
4. Copy link: exact deep link + rich-text clipboard; Open in browser via system browser.
5. QML: chevron only on the active tab with a submenu, right-click menu, Rename/Remove dialogs per spec.
6. Native Reload/Expand/Pop out/About/App permissions (research their UIs in the client first).
7. Side-by-side check vs winpc, docs, commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched from Teams' own client: menu builder (module 277379 We + 542104 filters), tab types (worker app-id table), order algorithm (worker 80574), dialogs (platform-modal), copy-link format (137308/407834/428148), rights rule (worker 74939); live menus read from winpc through the WebView2 debugger.
- Measured on winpc: Fluent menu (32 px items, gap 2, padding 6, radius 4; surface padding 4, shadow 16) and dialogs (600 wide, padding 24, radius 8, shadow 64, header/field/button offsets).
- Built: tabs from the middle tier (Page now shows), per-type menus in Rust with unit tests reproducing the live menus, Teams' move algorithm (one PATCH), rename/remove via UpdatePinnedTabs/DeletePinnedTab, Teams' Rename/Remove dialogs and errors, rich-text Copy link, shared MenuPopup now Fluent-exact everywhere, FluentSurface shadows.
- Verified: --tab-menu-test in OST Test Team (menus logged per tab, shots, rename/move/remove end to end); offscreen shots need QT_QUICK_BACKEND=rhi for shadows.
- Left: AC6 runtime clipboard check, AC7 browser open check, AC8 native Reload/Expand/Pop out/About/App permissions, AC9 full side-by-side.
<!-- SECTION:NOTES:END -->
