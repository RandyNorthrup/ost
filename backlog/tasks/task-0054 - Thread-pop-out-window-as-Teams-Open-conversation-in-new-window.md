---
id: TASK-0054
title: 'Thread pop-out window as Teams: Open conversation in new window'
status: To Do
assignee: []
created_date: '2026-11-07T13:28:00Z'
labels:
  - desktop
  - messages
dependencies: []
references:
  - docs/spec/messages-and-composer.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' channel post menu item 'Open conversation in new window' opens the thread in a child window (measured on winpc: 588 x 493 CSS px; title bar 'Team | Channel' with Settings and more and window controls; a #FAFAFA 61 px header with the team avatar, the channel name and 'Post by {author}', More channel options; the post card 526 wide with name and time stacked; replies; a 'Reply in thread' compose with Teams' side toolbar). OST needs a second conversation view bound to that thread's own data, with menus and pickers inside the child window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Open conversation in new window on a channel post opens a native child window showing that thread, laid out as Teams' pop-out
- [ ] #2 The window stays bound to its thread while the main window navigates elsewhere, and updates live
- [ ] #3 Replying, reacting, editing and the ··· menu work inside the pop-out
<!-- AC:END -->
