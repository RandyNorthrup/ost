---
id: TASK-0238
title: 'App bar app menu: Pin, Uninstall and Customize app bar as Teams'
status: To Do
assignee: []
created_date: '2026-11-20T18:48:00Z'
updated_date: '2026-11-20T22:00:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Right-clicking an app in Teams' app bar offers Open in new window, About, Share app, Pin/Unpin, Uninstall and Customize app bar. OST has the first three (TASK-0192).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app bar's right-click menu has Teams' Pin/Unpin, Uninstall and Customize app bar items and each works as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 research (winpc CDP + Teams 26304 bundles: appbar-control-tilecontextmenu, worker appBarManager pinApp/unpinApp/reorderApp): the menu is groups split by dividers — Open in new window | About, Share app, the app's own actions (Chat: New message Ctrl+N, New message in new window Ctrl+Shift+N) | Move up, Move down, Pin/Unpin | Uninstall | Customize app bar (bar only). About/Share only for platform apps (OneDrive, Copilot, Word…); Uninstall when canBeUnacquired (not core, state not InstalledAndPermanent/AdminPreInstalled/RequireConsent: Whiteboard, Planner, Workflows, Polly, Power BI, OneNote, Avatars, Updates, Viva Learning, SharePoint). Store's menu: Unpin | Customize (client pref appBar.isStoreUnpinned; Store then last in the flyout with Pin).
- Wire (captured): POST {mt}/beta/users/apps/pinned {appBarPinnedApps:[{appId, appBarOrder}]} — pin = max+1, unpin drops it and shifts later ones up, Move up/down = the visible neighbour's order (reorderApp shifts the apps between); changed apps first, then every other pinned app. Uninstall: "Remove {app}" / "Are you sure you want to remove {app}?" then DELETE {mt}/beta/users/apps/entitlements/{app}. Customize app bar = openSettingPage Appearance / app-bar-settings (card in view, Show app names focused).
- View more apps: unpinned personal apps (personal static tab, or a personal bot you installed; not PreConsented, mobile-only, the M365 calendar 5966c135, or ECS extensibility.appIdList), usage order then entitlement order.
- Built: api::app_bar (load, pin/unpin/move bodies, flyout rules, usage sort; unit tests from the captures), store_request appBar/appBarChange (icons through the private image cache), AppRail data-driven bar (Teams' pinned order, Copilot tile, Ctrl+1… by position), Teams' tile menu and flyout menu, flyout from your apps (300 wide, centred on the button), Remove dialog, Store unpin, Customize → SettingsView.showSetting with Teams' focus outline on the switch; harness --app-bar-test.
- Live (linuxlt, spatest = ost-test1): every bar tile's menu equals Teams' (except Open in new window only on hosted apps); flyout list equals Teams' (Workflows moved up by a newer use); pin Word → 10, Move up → Word 9/Copilot 10, Unpin → Copilot 9 (same as Teams' captures); Store unpin/pin; Customize opens Appearance with the focus ring; Uninstall Polly from the flyout (dialog, DELETE, gone after reload; Polly re-added afterwards with examples/add_app). Orders put back exactly (Activity 1, Chat 3, Chat-separate 4, Teams 5, Calendar 6, Calls 7, OneDrive 8, Copilot 9) after the measuring moves.
- Open: Open in new window for Teams' own apps (Activity, Chat, Calendar, Calls, OneDrive, Events) — OST has no window for those views yet; bots' "Block bot conversation" item.
<!-- SECTION:NOTES:END -->
