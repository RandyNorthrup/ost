---
id: TASK-0040
title: Channel tabs behave exactly as Teams desktop (per docs/spec/channel-tabs.md)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:35:00Z'
updated_date: '2026-11-09T16:43:00Z'
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
- [x] #6 Copy link to tab writes Teams' exact deep link (channel or entity form) as rich text with the tab name
- [x] #7 Open in browser opens the tab's website URL in the system browser
- [x] #8 Reload tab, Expand tab, Open tab in new window, About this tab and App permissions act on OST's native tab views as Teams' do
- [x] #9 Verified side by side against Windows Teams on winpc in OST Test Team
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

- AC6 verified at runtime: OST's Copy link to tab is byte-identical to Teams' clipboard (read on winpc) for the Notes (entity form) and Page (channel form) tabs. That meant dropping `groupId` from the link and adding `itemprop="teams-copy-link"` to the HTML.
- AC7: Teams' Open in browser opens the tab's websiteUrl (Notes: https://onenote.com/, which redirects to onenote.cloud.microsoft). OST opens the same URL in the system browser.
- Harness: --tab-link-test=<tab> --open-chat=<channel> copies the link and holds 20 s for wl-paste.

- AC8 (part): App permissions is Teams' dialog (measured on winpc): the app's device permissions from its manifest, Teams' strings, switches defaulting on for ECS autoApprovedDevicePermissionApps, and "Learn more". Changes are kept per device in OST settings, and OST's web views grant camera, microphone, location and notifications only as the app's permissions allow (no other permission is ever granted). Verified with OneNote in OST Test Team: the dialog matches Teams, and turning the switch off and on is read back.
- Still left in AC8: Expand tab and Open tab in new window. The Notes tab itself waits on TASK-0053.

- AC8 done:
  - Expand tab is Teams' full-screen tab: the chat list goes and the tab's header replaces the channel's (app icon in Teams' squircle, tab name, Collapse tab); leaving the tab, channel or app collapses it.
  - Open tab in new window (TabWindow.qml): Teams' child window titled "team / channel", with the app's header and actions (Reload, Go to website, Copy link, About, App permissions); a Page opens alone in a window titled OST.
  - Reload tab now works (it was emitted but unhandled): Shared opens the folder afresh, a Page reloads.
  - All of it measured on winpc and matched within a pixel (`--tab-window-test`).
- Follow-ups: tab conversations (TASK-0079), drag to reorder (TASK-0080).

- AC9: every item compared live with Teams on winpc in OST Test Team > General: the menus per tab (11-06), Rename/Move/Remove end to end, Copy link (byte-identical), Open in browser, App permissions, About, and Expand / Open in new window (11-09, pixel-checked). The Notes tab's own content is TASK-0053.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel tabs behave as Teams desktop's, from the middle tier's pinned tabs to every menu action.

Changes:
- Tabs come from the middle tier, including the channel Page. Menus are built in Rust exactly as Teams builds them per tab type: the chevron on the active tab, the right-click menu, and disabled moves.
- Moving, renaming and removing go through Teams' pinned-tabs calls. Teams' order algorithm makes one PATCH.
- Rename and Remove dialogs match Teams' platform modal.
- Copy link to tab is byte-identical to Teams' clipboard.
- Open in browser opens the tab's website.
- App permissions: Teams' dialog. OST's web views honour it.
- About this tab is now its own component (TabAboutDialog.qml).
- Expand tab: full screen with the tab's header (app icon in Teams' squircle, tab name, Collapse tab). Navigating away collapses it.
- Open tab in new window: TabWindow.qml (Teams' child window, app header, Reload / Go to website / Copy link / About / App permissions). A Page opens alone.
- Reload tab: Shared opens its folder afresh, and a Page reloads.

Tests:
- tabs unit tests (menus per type, order, copy link)
- harnesses on linuxlt: `--tab-menu-test`, `--tab-link-test`, `--tab-perms-test`, `--tab-window-test`
- compared with Teams on winpc (CDP measurements and VNC captures)

Follow-ups:
- TASK-0079: tab conversations
- TASK-0080: drag to reorder
- TASK-0053: Notes content (needs the SPA sign-in)
<!-- SECTION:FINAL_SUMMARY:END -->
