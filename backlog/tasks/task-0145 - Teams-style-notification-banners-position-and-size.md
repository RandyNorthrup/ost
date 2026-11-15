---
id: TASK-0145
title: Teams-style notification banners (position and size)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T03:46:00Z'
updated_date: '2026-11-15T16:13:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop shows its own notification banners (NotificationStyleList Win10: "Purple"). Settings ▸ Notifications ▸ Display sets their position on the screen (bottom right, top right, bottom left, top left; updateNotificationCornerPosition) and size (Comfy or Compact; notificationCrossCloudSettings.sizeTheme). OST hands notifications to the desktop's notification service, which places and sizes them itself. Matching Teams means OST drawing Teams' banner window itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST shows Teams' notification banner (layout, actions, timing) instead of the system's
- [x] #2 Position on the screen and Size in Settings place and size it as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams' window measured on winpc with its Test notification (CDP on the toasts window, all four corners, both sizes; settings put back to Bottom right / Comfy). Message toasts don't show on winpc because Windows notifications are off there (left alone).
- Layout, queue and timers taken from notifications-app / 344132 (NotificationStateContainer) and the Griffel CSS.
- Wayland placement through LayerShellQt loaded at run time (dlopen); X11 moves the window. GNOME Wayland (no layer shell) keeps the desktop's notifications.
- Verified on linuxlt (KDE Wayland): all four corners, Comfy and Compact, a real message from OST Test 2 (OST TEST 146) answered from the banner (heart + OST TEST 147 quick reply), Dismiss clicks via uinput.
- Follow-up: TASK-0160 (compact incoming-call card).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now draws Teams' own notification banners instead of handing them to the desktop's notification service, placed and sized by Settings ▸ Notifications ▸ Display.

Changes:
- NotificationBanners.qml: Teams' banner window (372 wide, flush with the screen side, 90 px from the top/bottom of the work area) with up to three 360-wide #444791 cards. Standard card Comfy (124, 164 with quick reply) and Compact (76); meeting-started card (260/130, Join + Message); test banner (bell); the incoming call moved in as a card (IncomingCall.qml is now an Item).
- Teams' queue: calls > meetings > messages, oldest first, three on screen, oldest nearest the corner; display time from Settings (meetings 20 s, waiting ones 30 s); hover/focus holds, 250 ms / 2 s rule.
- Actions: open the chat (respects Opening content), More options ▸ Go to Notification settings, quick reaction (your quick reactions, skin tone) with Teams' 2 s overlay, quick reply (Enter sends), compact Reply on hover, Dismiss.
- Wording per Teams (1:1 sender / "sent an urgent message", group "<sender>: <text>", "@mentioned you" [in a thread] over the chat or channel), urgent badge; the desktop sound theme's message sound unless silent.
- native.cpp: X11 placement; Wayland layer-shell via LayerShellQt (dlopen, optional). Backend: banner_requested signal, banner_support/prepare/place, banner_reply, banner_react, open/join_from_notification, notification_sound; OST_SYSTEM_NOTIFICATIONS=1 keeps desktop notifications.
- Engine: pushed messages carry their id and thread root.
- Settings ▸ Display: Position on the screen and Size tiles (Teams' pictures), rows at Teams' 44 px pitch; only shown where OST draws banners.

Tests: event_hub tests (id, thread root); desktop crate tests; --notif-banner-test (all corners/sizes, screenshots), --notif-banner-test=hold with uinput clicks, --notif-banner-live-test with a real message (reply and reaction confirmed on the service); --cards-test=Display (differs from Teams only by Windows' taskbar-flashing line).

Follow-up: TASK-0160 compact incoming-call card.
<!-- SECTION:FINAL_SUMMARY:END -->
