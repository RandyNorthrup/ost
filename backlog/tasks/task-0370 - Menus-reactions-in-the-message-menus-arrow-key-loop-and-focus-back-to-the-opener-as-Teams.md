---
id: TASK-0370
title: >-
  Menus: reactions in the message menu's arrow-key loop, and focus back to the
  opener, as Teams
status: Done
assignee:
  - '@t370'
created_date: '2026-11-27T20:53:00Z'
updated_date: '2026-11-28T01:57:00Z'
labels:
  - desktop
  - accessibility
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0362 (PR #48). In Teams the message menu's reactions strip is part of the menu's arrow-key loop; in OST it isn't. And in Teams Esc/Shift+Tab put the focus back on the button that opened the menu; in OST most buttons can't take focus, so after a click focus returns to whatever had it before.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a message's ··· menu the reactions strip is reached and moved through with the arrow keys exactly as in Teams desktop, and Enter/Space reacts
- [x] #2 After a menu opened by clicking a button closes with Esc or Shift+Tab, keyboard focus is on that button, as in Teams
- [x] #3 The --menu-keys-test harness covers both, and passes
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams desktop (testpc1, ost-test1, UIA focus log + screenshots): right-click message menu reactions order, Left/Right, Home/End, Esc/Tab/Shift+Tab focus for the hover bar ··· and the chat list ··· More list options.
2. MenuPopup: header keyItems as the first stops (focus, outline, Enter/Space activate); opener (explicit or the parent button) gets the focus on Esc / Shift+Tab, Tab goes on from it; closing flag so the hover bar stays up until the focus is back.
3. MessageHost reaction strip: keyItems, activate(), outlines; BarButton and ChatList HeaderButton: outline, Enter/Space, tooltip on focus; HoverBar stays up while its ··· has the focus.
4. --menu-keys-test: header + button-opener test menu, the message right-click menu and ··· More options (signed in); red drill against origin/main's MenuPopup.
5. Live run on a test PC, docs/desktop.md row, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Teams desktop research (2026-11-27, testpc1 Teams desktop as ost-test1, chat Customer feedback; UIA FocusedElement logged after each key from a console-session task, plus screenshots; no picks, no reactions):
- Right-click message menu: opens with the focus on Like (no outline). Down: Like, Heart, Laugh, Surprised, More reactions, Reply with quote, Edit, Forward... Up from Like wraps to More actions; Home = Like, End = More actions; Left/Right don't move (on reactions or rows). Esc puts the focus on the message. Outline on a reaction: 2 px black, radius 4, around the 32 px button.
- Hover bar ··· More options: the menu (no reactions) opens on Reply with quote; Esc puts the focus on ··· (outlined, tooltip showing, the bar stays up while it has the focus); a second Esc goes to the message. Shift+Tab -> the bar's previous button (Edit), Tab -> ··· itself (the hover bar is a toolbar; not copied: OST's bar has no Tab order).
- Chat list ··· More list options: Esc -> the ··· button; Shift+Tab -> the ··· button; Tab -> the next header button (Show filter text box).
- winpc's Teams was in use by another agent (search typing over CDP), so it was not touched. On testpc1 one last 'clear the outline' click at a blank spot landed while another agent had switched Teams to a channel thread (no action taken there).

Implementation:
- MenuPopup.qml: a header's keyItems are the first keyboard stops (part "header"): focus, Fluent outline once a key is used, Enter/Space call activate()/clicked(); Left/Right don't move; typeahead skips them; rows' outline hidden then.
- MenuPopup.qml: opener (explicit, or the parent when it has a clicked signal: BarButton, ChatList HeaderButton); Esc and Shift+Tab put the focus on it (Qt's Popup may already have restored the old focus item, so the 'pick moved the focus' guard is skipped for them); Tab goes on past it; picks still give the focus back to where it was (compose keeps typing after a pick). closing flag (aboutToHide..closed) so a host can keep the opener visible.
- MessageHost.qml reaction strip: keyItems (quick reactions + More reactions), activate(), outlines. BarButton: outline while focused, Enter/Space, tooltip on focus. ChatList HeaderButton: outline, Enter/Space. HoverBar: stays up while its ··· has the focus; Conversation/menuOpenFor keep it up while the menu is closing.
- MenuKeysTest.qml: header + BarButton-opener test menu; More list options Esc -> its ··· button; a 1:1 chat's newest message: right-click menu loop through the reactions, ··· More options focus after Esc with the bar up, second Esc. Hooks: Conversation.messageMenuForTest/hoverBarForTest, HoverBar.moreButtonForTest. docs/desktop.md row.

Live (testpc2 WSLg, OST Test 3, own test-harness build of this branch, QML iterated with OST_QML_DIR): --menu-keys-test 80 ok / 0 FAIL. Red drill (origin/main's MenuPopup.qml, rest of this branch): 18 FAIL, all new checks. Screens: More reactions outlined in the right-click strip; ··· outlined with the bar up after Esc. Mic: ost_t370_mic only (no alsa_input streams; WSL has none).
Not checked live: Enter/Space on a real reaction in the strip (would react on a test chat); covered by the harness's header test, the strip's activate() is the same code its tap runs.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The message right-click menu's reactions are in its arrow-key loop and menus opened from a button give it the focus back on Esc / Shift+Tab, as Teams desktop (measured on testpc1).

Cause: MenuPopup's header strip was outside its keyboard stops, and on close the focus went back to whatever had it before (OST's buttons don't take the focus when clicked, unlike Teams').

Changes: MenuPopup header keyItems as the first stops (opens on Like; Down through the reactions and More reactions to Reply with quote; Up from Like wraps to More actions; Enter/Space react); an opener (explicit or the parent button) that gets the focus on Esc and Shift+Tab, Tab going on past it, picks unchanged; BarButton and ChatList HeaderButton show Fluent's outline and take Enter/Space when focused; the hover bar stays up while its ··· has the focus.

Tests: --menu-keys-test 80 ok / 0 FAIL live on testpc2 (OST Test 3), incl. the real message menu and ··· More options; red drill with main's MenuPopup: 18 FAIL.

Not copied: Teams' hover-bar Tab / Shift+Tab (its toolbar's own tab order). Not checked live: Enter on a real reaction (harness covers the same path). Other buttons that open menus get the focus but no outline yet.
<!-- SECTION:FINAL_SUMMARY:END -->
