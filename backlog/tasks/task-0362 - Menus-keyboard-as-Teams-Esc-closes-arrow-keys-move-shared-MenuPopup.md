---
id: TASK-0362
title: 'Menus keyboard as Teams: Esc closes, arrow keys move (shared MenuPopup)'
status: Done
assignee:
  - '@task-0362-agent'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T19:39:00Z'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-08: OST's menus ignore the keyboard: Esc doesn't close them, arrow keys don't move through items; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' Fluent menu keyboard behaviour (Teams web = the desktop client's app, via CDP): opening, arrows, wrap, Home/End/PageUp/PageDown, typeahead, Enter/Space, Left/Right with split rows and submenus, Esc, Tab, focus return, focus ring.
2. Implement it once in MenuPopup.qml: the popup takes focus on open, a keyboard "current" stop (row + split part) shared with hover, Fluent focus outline, key handling with ShortcutOverride so window Shortcuts (Escape) don't steal keys, submenus opened by keyboard focus their first item, focus restored on close.
3. Keep menus with their own handling working (TitleBar dropdowns open with keys; onClosed focus handlers).
4. Add a --menu-keys-test harness (real key events through QtTest, like --keys-test) checking several menus incl. one with a submenu.
5. Build on a WSL box, run the harness and check live on linuxlt (OST Test 3) side by side with Teams.
6. PR task-0362-menu-keyboard; drive CI/CodeQL/Codex to green.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Teams research (2026-11-27, Teams web as OST Test 3 in headless Chrome on linuxlt over CDP; chat list ··· "More list options" and a message's right-click menu):
- Click opens with focus on the first item, no ring; Enter/Space on the focused trigger opens with the first item focused and the ring visible. ArrowDown on the trigger does not open (toolbar arrow nav).
- Down/Up move and wrap (last -> first, first -> last). Home/PageUp = first, End/PageDown = last.
- Typeahead: one character, next item (after the current, wrapping) whose label starts with it; "c","c" cycles Collapse all sections -> Customize view; no match = stays.
- Split row (Mark all as read | chevron): both parts are stops in the Down order; Right on the label part -> chevron part, Left back; Right/Enter/Space on the chevron part opens the submenu with its first item focused.
- Submenu row (Translation >, More actions >): Right/Enter/Space opens it, first item focused; Left or Esc closes only the submenu, focus back on its row. Hover-opening a submenu also moves focus to its first item; hovering an item focuses it (hover and keyboard share one focus).
- Esc closes and focus returns to the trigger (the message for a right-click menu). Tab closes and focus moves to the element after the trigger; Shift+Tab closes with focus on the trigger.
- Focus ring: 2 px #000 (strokeFocus2) outline 2 px outside the row, radius 4; no hover fill. The row whose submenu is open keeps the hover fill.
- Message menu: the reactions header is in the same circular order (More actions -> Like); not done in OST (header is a separate component).

Implementation (MenuPopup.qml, once for all ~177 menus):
- The popup takes the focus (focus: keyboardNavigation, default true); the keyboard's row (current + currentPart for a split's chevron part) is shared with hover and gets the real focus (screen readers follow it); Keys on the content Column, with Keys.onShortcutOverride so a window Shortcut on Escape (Help, Feedback, PreJoin windows, drags) doesn't take the menu's Esc. Ctrl/Alt/Meta chords pass through.
- Stops: every row but separators, headings and group labels; disabled rows are stops (Fluent disabledFocusable) but Enter does nothing. A split row with a submenu has two stops.
- Submenus (the same component, made on first use) get ownerMenu; opened by Right/Enter/Space or hover they take the focus on their first row; Left/Esc close only them and the owner takes the keys back on the row. The row whose submenu is open keeps the hover fill (as Teams).
- Focus returns on close to the item that had it before opening (only if the pick didn't move it on purpose); Tab also moves on to the next item in the focus chain.
- A row whose `keys` is one letter (or Del) is picked by it: Teams' message menu Q/E/F/S/P/U (seen in Teams: S saved and U marked unread with the menu open).
- Right on a `chevron` row (OST's message menu Translation / More actions, separate menus today) picks it like Enter.
- Keyboard-opened menus: TitleBar's status/duration dropdowns set focusRing after open(); Conversation's selected-text menu keeps the body's selection (persistentSelection while open) since the menu now takes the focus.
- Harness --menu-keys-test (MenuKeysTest.qml) with real key events; docs/desktop.md row.

PR #48 opened (live checks pending in its body).

Codex review on #48 (3 findings, fixed in 528ef3fd, threads answered and resolved): row chords (Ctrl+C/Ctrl+A of the text menu) pick their row; focus goes to the accessible row item (wrapper for disabled rows); persistent split labels stay open on Enter.
Live (linuxlt, OST Test 3, own test-harness build): --menu-keys-test 46 ok / 0 FAIL, incl. More list options (split + submenu) and a chat ··· menu (typeahead to Move to section, its submenu). Screens compared with Teams web shots (outline, split part, submenu row fill).
Teams side effects of the research: on OST Test 3's web session, pressing s / u in a message menu saved/unsaved and marked unread one message in the 1:1 chat with OST Test 2 (Teams' accelerators); the menu shows "Save this message" again, so it ended unsaved.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's menus now take the keyboard as Teams' Fluent menus do (PR #48).

Cause: MenuPopup.qml (the one menu component, ~177 uses) never took the focus and had no key handling.

Changes (MenuPopup.qml, so every menu gets them):
- takes the focus on open, first row current (no outline after a click); Down/Up wrap; Home/PageUp, End/PageDown; typeahead; a row's own keys/chord picks it; Enter/Space pick or open a submenu; Right/Left for split parts and submenus; Esc closes (a submenu only), Tab/Shift+Tab close and move on; focus restored to what had it.
- hover and keyboard share the row; the row's accessible item has the real focus; Fluent focus outline once a key is used, only in the menu holding the keys; an open submenu's row keeps its fill.
- Keys.onShortcutOverride so window Escape shortcuts don't steal the menu's keys.
- TitleBar dropdowns show the outline when opened by keys; the selected-text menu keeps the selection.

Tests: --menu-keys-test (MenuKeysTest.qml, docs/desktop.md): 46 checks pass live on linuxlt (OST Test 3), including More list options and a chat's ··· menu with submenus.

Unverified: physical keyboard on linuxlt (QtTest key events used); header strips (message reactions) not in the arrow order as in Teams; Teams' disabled-item focus taken from Fluent source; focus returns to the prior focus item rather than to non-focusable trigger buttons.
<!-- SECTION:FINAL_SUMMARY:END -->
