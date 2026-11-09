---
id: TASK-0065
title: 'Taskbar badge as Teams: unread count, else presence'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T01:42:00Z'
updated_date: '2026-11-09T01:42:00Z'
labels:
  - desktop
  - shell
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams on Windows overlays its taskbar button: the app bar's unread total (Activity + Chat unread conversations) as a red numeric badge, or with nothing unread your presence glyph in a white ring. OST should show the same on Linux taskbars.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The window icon carries Teams' overlay: #C42B1C count badge (1-99, 99+) or the presence glyph (Away #EAA300, Busy/DnD #C50F1F) at the bottom-right, measured on winpc
- [x] #2 Desktops that draw launcher badges (KDE Plasma's task manager, GNOME docks) show the unread count via the freedesktop launcher API
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research on winpc: Teams sends {icon:{countBadge:{value}}} or {icon:{glyphBadge:{glyph:presence}}} to its host (services-global-taskbar); count = sum of the app-bar badges (r_data-resolvers-taskbar). Count badge stays red (#C42B1C) with any presence (tested by setting Appear away); with 0 unread the glyph follows presence (Away #EAA300, Busy/DnD #C50F1F, white ring). Overlay 16 px on a 24 px icon, 1.33 px past its corner. Statuses on winpc reset afterwards.
- linuxlt KDE: Qt 6.11 sends the icon via xdg-toplevel-icon, but Plasma's task manager draws the .desktop icon, so it shows the count through the launcher API badge instead; the overlay shows where window icons are used (X11 taskbars, Alt+Tab).
- The user's Hyprland waybar has no taskbar module (workspaces + tray), so neither applies there; the tray keeps Teams' tray presence badge.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' taskbar badge for OST.

- native.cpp draws Teams' overlay into the window icon at each size: the unread total on a #C42B1C circle (99+ above 99), else your presence glyph in a white ring.
- launcher_badge.rs publishes the same count over com.canonical.Unity.LauncherEntry for KDE/GNOME task managers.
- Main.qml adds up the app bar badges (Activity + unread unmuted chats) and passes presence.
- OST_DUMP_BADGE=<dir> saves the rendered icons for checking.

Verified: rendered icons compared with winpc's taskbar at the same scale (count and busy glyph); KDE on linuxlt shows the count badge.
<!-- SECTION:FINAL_SUMMARY:END -->
