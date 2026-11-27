---
id: TASK-0370
title: >-
  Menus: reactions in the message menu's arrow-key loop, and focus back to the
  opener, as Teams
status: To Do
assignee: []
created_date: '2026-11-27T20:53:00Z'
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
- [ ] #1 In a message's ··· menu the reactions strip is reached and moved through with the arrow keys exactly as in Teams desktop, and Enter/Space reacts
- [ ] #2 After a menu opened by clicking a button closes with Esc or Shift+Tab, keyboard focus is on that button, as in Teams
- [ ] #3 The --menu-keys-test harness covers both, and passes
<!-- AC:END -->
