---
id: TASK-0332
title: No unread badge on the KDE Plasma taskbar
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T16:17:00Z'
labels:
  - bug
  - shell
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). OST's unread count doesn't show on the Plasma taskbar (Teams shows its badge on the Windows taskbar).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The unread count shows on the Plasma task manager (Unity LauncherEntry API) and on other desktops that support it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Check why Plasma ignores the existing LauncherEntry Update signal (journal)
2. Register a desktop entry for unpackaged runs; answer Query; resend after registering
3. Live-check the Plasma taskbar badge on linuxlt
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: OST already sent com.canonical.Unity.LauncherEntry.Update, but Plasma's task manager drops it ("Failed to find service for Unity Launcher application://io.github.RandyNorthrup.ost.desktop" in plasmashell's journal) unless a desktop entry with that id is installed. Packages install one; an OST run from a build folder, tarball or AppImage has none (linuxlt only had the pre-0.2.1 ost-desktop.desktop).
- Fix: launcher_badge::register_desktop_entry() at start writes ~/.local/share/applications/io.github.RandyNorthrup.ost.desktop (Exec = the running binary or the AppImage, marked X-OST-Generated) and the 256 px icon when no entry with that id exists in the XDG data dirs; it rewrites only its own entry, once that binary is gone; never in Flatpak or Snap. After writing it sends the count again (5 s, 20 s). The launcher entry object also answers Query (/com/canonical/unity/launcherentry/ost), as libunity apps do. Count rules unchanged (Main.qml taskbarCount: unread unmuted chats + Activity).
- Live (linuxlt Plasma 6.6 Wayland, spatest = ost-test1): entry and icon written; no more "Failed to find service" lines; Query answers (app uri, count, count-visible); marking a chat unread sent Update {count 1, count-visible true} and Plasma's task manager showed "1" on the OST button; marked read again -> 0.

- Codex review (PR #19): Exec now escaped for both stages (argument quoting, then the entry's string escapes); paths with % are not written (GLib drops %%-escaped binaries). Checked by launching generated entries through Gio.DesktopAppInfo (spaces, quotes, backslashes, $, backticks). PR #19.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The unread count shows on the KDE Plasma task manager (and other docks that read the Unity launcher API) also when OST runs outside a package.

Cause: Plasma drops LauncherEntry updates for an app id without an installed desktop entry ("Failed to find service for Unity Launcher"), which every unpackaged OST run lacked.

Changes (launcher_badge.rs, main.rs): OST writes its own desktop entry and icon for the user when none with its id is installed (rewrites only its own, once its binary is gone; never in Flatpak or Snap) and sends the count again; the entry object answers Query. Count rules unchanged. Unit tests for reading Exec, quoting and when to write.

Tests: live on linuxlt, Plasma 6.6 Wayland: entry written, the Plasma error gone, Query answered, an unread chat showed 1 on OST's taskbar button and 0 after reading it. Not tested: GNOME docks.

PR #19 (branch task-0332-launcher-badge).
<!-- SECTION:FINAL_SUMMARY:END -->
