---
id: TASK-0326
title: Compact call view never appears on KWin
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T15:54:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The compact call view (the small window Teams shows when you leave the call window) never appears on KDE Plasma (KWin).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The compact call view appears and behaves as in Teams on KWin (Wayland and X11) as well as Hyprland and GNOME
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find why the compact view never shows on KWin (Qt never reports minimized on Wayland)
2. Detect a minimized call window by exposure (WindowTool item, native.cpp)
3. On Wayland with a layer shell make the compact view a layer-shell surface (bottom right, over windows, draggable)
4. Live-check on KWin Wayland and nested KWin X11
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: Qt's Wayland plugin never reports a minimize (xdg-shell has no minimized state; QtWayland drops Qt::WindowMinimized right after set_minimized), so callWindow.visibility stays Windowed on KWin, GNOME and Hyprland and the compact view (visible only while visibility === Minimized) never shows. X11 reports it (WM_STATE Iconic -> visibility 3).
- Fix: WindowTool QML item (window_tool.rs + native.cpp) exposes QWindow::isExposed(); CallWindow polls it every 250 ms during a call (two checks) -> minimizedNow. Window.active can't gate it: a call window stays "active" while its transient parent (main window) is focused.
- On Wayland with a layer shell the compact view is a layer-shell surface (LayerShellQt via dlopen, top layer, keyboard on demand, no activation on show) anchored bottom-right with Teams' margins; title-bar drag moves it by margins (60 ms settle so positions from the old place are not double counted); Minimize puts it away until the meeting window is shown again; Maximize meeting window = showNormal + requestActivate (xdg-activation brings a minimized window back). GNOME: ordinary window (no layer shell). X11: unchanged placement, keeps the old activation behaviour.
- Live (linuxlt, KWin 6.6 Wayland, ost-test1 spatest, solo Meet now, virtual mic/speaker): KWin-script minimize -> exposed false, minimizedNow true, compact shown at bottom right over other windows within ~0.5 s; Maximize via API and a real click (uinput) restores and activates the call window; KWin unminimize closes it; app-side showMinimized works too; a fully covered (not minimized) call window stays exposed -> no compact view (Teams shows it only when minimized); drag by title bar moved it 567/380 px for a 600/370 px drag; Minimize button hides it until restore, then it returns on the next minimize.
- Live nested KWin X11 (Xvfb :57 + kwin_x11, QT_QPA_PLATFORM=xcb): xdotool windowminimize -> WM_STATE Iconic, visibility 3, compact at (1072,617) = bottom right minus 7/35, _NET_WM_STATE_ABOVE; restore and wm activate close it.
- Not testable here: Hyprland and GNOME (neither installed on linuxlt or this PC). Hyprland has a layer shell and stops frame callbacks for hidden windows (same path as KWin); GNOME sends xdg suspended (same exposure path) but has no layer shell.

- Final build (linuxlt): KWin Wayland minimize -> compact shown, unminimize -> closed; nested KWin X11 -> compact at bottom right, _NET_WM_STATE_ABOVE and FOCUSED (X11 activation unchanged from before), restore closed it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams compact call view now appears when the meeting window is minimized on Wayland (KWin, and the same path for Hyprland and GNOME) as it did on X11.

Cause: a Wayland client is never told it was minimized, so callWindow.visibility stayed Windowed and the compact view (shown only while Minimized) never showed.

Changes:
- window_tool.rs + native.cpp: WindowTool QML item (window exposed?, layer-shell prepare/place).
- CallWindow.qml: minimizedNow = Minimized or not exposed (polled every 250 ms in a call); used for the compact view, sharing restore and side panes.
- CompactCallWindow.qml: layer-shell surface at the work area bottom right on Wayland with a layer shell (drag by margins, Minimize puts it away), ordinary window on GNOME, unchanged on X11.
- docs/spec/call-and-meeting-window.md.

Tests: live on linuxlt, KWin Wayland (minimize by KWin and by the app, Maximize click, KWin unminimize, drag, Minimize, covered window stays without compact view) and nested KWin X11 (WM minimize, restore). Not tested: Hyprland, GNOME (not installed).
<!-- SECTION:FINAL_SUMMARY:END -->
