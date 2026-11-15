---
id: TASK-0145
title: Teams-style notification banners (position and size)
status: To Do
assignee: []
created_date: '2026-11-15T03:46:00Z'
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
- [ ] #1 OST shows Teams' notification banner (layout, actions, timing) instead of the system's
- [ ] #2 Position on the screen and Size in Settings place and size it as in Teams
<!-- AC:END -->
