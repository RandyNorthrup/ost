# Tray icon and app lifecycle — Teams desktop behaviour (spec)

The tray belongs to Teams' native Windows host (ms-teams.exe), not the web
client, so its strings aren't in the client bundles. Everything here was
read from the real app on winpc (ost-test1, build 26276.513) on 2026-11-06,
or comes from docs/parity/shell-settings.md.

## Tray icon
- The Teams icon carries the user's **presence badge** (a green check for Available).
  OST uses its own logo with the same badge.

## Tray menu (right-click), in order
1. **Account row**: the app icon with the presence badge, then "`{display name}` | `{organization}`"
   ("OST Test 1 | Secure Coast Network Solutions"). Selecting it opens the main window.
2. **Status**: the current status's presence icon and name ("Available"), with a submenu ›:
   - Available (green check)
   - Busy (red dot)
   - Do not disturb (red minus)
   - Be right back (yellow clock)
   - Appear away (yellow clock)
   - Appear offline (grey ⊗)
   - divider
   - **Reset Status** (refresh icon)
3. divider
4. **Help** ›, with one item: **Collect Support Files**. Teams brings its window forward and
   shows a full-width info banner under the title bar, "Downloading web logs...". It writes, to the
   **Desktop**, a folder "MSTeams Support Logs YYYY MM DD HH MM SS" (local time) and
   "PROD-WebLogs-<UTC ISO time>.zip", then opens File Explorer at the Desktop.
5. **Quit Teams**. This is the only place the app actually quits
   (docs/parity/shell-settings.md: Quit lives only in the tray).

Submenus open to the left of the menu when there's no room on the right
(Windows' own menu placement). The menu uses the Windows system menu
style, not Fluent.

## Lifecycle
- Settings › General › "On close, keep the application running" is on by
  default. Closing the window then hides it, and the app keeps running in the tray.
- Launching Teams again brings the running instance forward; a second
  instance never starts.
- Left-clicking the tray icon opens and raises the main window.

## OST mapping (Linux)
- **Tray**: a StatusNotifierItem through Qt's platform tray, the same menu, and the
  OST logo with the presence badge.
- **Quit**: "Quit OST", the OST equivalent of "Quit Teams"; OST keeps its own name and logo.
- **Collect Support Files**: an "OST Support Logs YYYY MM DD HH MM SS" folder on the
  Desktop, holding OST's log (`$XDG_STATE_HOME/ost/ost-desktop.log`) and its version; then the
  Desktop opens. OST has no separate web logs, so it has no zip and no "Downloading web logs..." banner.
- **Single instance**: a socket in `$XDG_RUNTIME_DIR`. A second launch tells the first
  to raise its window, then exits.
