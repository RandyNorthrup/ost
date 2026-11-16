---
id: TASK-0166
title: >-
  Title bar ··· menu as Teams: every item (Premium, Cast, Downloads, Zoom, Get
  the mobile app)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T00:26:00Z'
updated_date: '2026-11-16T01:39:00Z'
labels:
  - desktop
  - shell
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' title bar Settings and more menu (measured 2026-11-15): 229 wide with 32-tall rows. Its items are Unlock Teams Premium, (separator), Pin window on top, Settings, Cast, Downloads, (separator), the Zoom row (— (100)% + and reset), (separator), Help, Feedback ›, Keyboard shortcuts, and Get the mobile app (New pill). OST's menu is 360 wide with 36-tall rows and has only Pin, Settings, Help, Feedback and Keyboard shortcuts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's ··· menu has Teams' items, order, separators and geometry
- [x] #2 Zoom out, Zoom in and reset scale OST's whole window as Teams does, with Teams' steps and Ctrl+-, Ctrl+= and Ctrl+0
- [ ] #3 Downloads, Get the mobile app, Cast and Unlock Teams Premium open what Teams' open, measured on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-15: built and checked against Teams on winpc (docs/spec/settings-and-more.md).
  - Menu: Teams' items, order, dividers and geometry. The popover is 238.47 wide and centred under ···, with 32-tall rows, the Zoom row and the New pill. Icons premium-20, cast-20 and page-fit-20 were added from Fluent.
  - Zoom: 60–400% in 5% steps, measured. Ctrl+- / Ctrl+= / Ctrl+0. The whole window scales (root item scale with the layout size divided by the zoom; checked at 150% with a screen capture). Kept in zoomPercent.
  - Unlock Teams Premium: shown while the authsvc lfts/TeamsPremium self-serve policy and eligibility allow it (api::premium; ost-test1: ENABLED, eligible). The dialog matches Teams'. Start trial POSTs …/acquire/ and uses Teams' strings for the steps; their own dialogs aren't measured (no trial started).
  - Cast: Teams' dark Cast window, searching for 20 s (measured 20.3 s), then "Didn't find any Teams Rooms nearby…". Room beacons belong to TASK-0161.
  - Downloads: Teams shows WebView2's downloads hub; OST's flyout matches it (header buttons, rows, Removed, search, Clear all with its confirmation, empty text), listing OST's own downloads (api::downloads, recorded by files::save_unique and the biometric export).
  - Get the mobile app: dialog with Teams' QR code and store badges.
  - Teams' download history on winpc was cleared while measuring the empty state.
  - Left (AC3): measure Start trial's pending, success and error dialogs (needs a Premium trial started on a test account).
<!-- SECTION:NOTES:END -->
