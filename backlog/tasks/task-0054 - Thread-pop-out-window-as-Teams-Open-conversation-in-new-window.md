---
id: TASK-0054
title: 'Thread pop-out window as Teams: Open conversation in new window'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T13:28:00Z'
updated_date: '2026-11-09T17:29:00Z'
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
- [x] #1 Open conversation in new window on a channel post opens a native child window showing that thread, laid out as Teams' pop-out
- [x] #2 The window stays bound to its thread while the main window navigates elsewhere, and updates live
- [x] #3 Replying, reacting, editing and the ··· menu work inside the pop-out
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched on winpc: "Open conversation in new window" opens a 588 x 493 child window; header, card, reply layout, day dividers, hover bars and the More channel options menu were measured (docs/spec/messages-and-composer.md).
- Data: the reply chain `GET conversations/{channel};messageid={post}/messages` (probed live) returns the post and its replies. The backend keeps each open thread loaded (`open_thread_window` / `close_thread_window`, `thread_windows_json`), reloads it on Trouter pushes for its channel, and shows sends in progress (outbox lies).
- Actions: the backend now routes a message action to the conversation that shows the message (`chat_of`), so reactions, edit, delete, save, pin, translate, forward, mark unread and follow work from the window. Replies and files go to the thread (`send_thread_reply`, `send_thread_files`).
- UI: Conversation's menus, pickers, who-reacted and edit state moved into MessageHost.qml (the main chat's regression harnesses still pass). ThreadWindow.qml has its own host, so its menus open in its own window. MessageText.qml is shared.
- Verified live (`--thread-window-test`): with the main window moved to OST group test, a reply sent from the window, a Like on it and an edit all showed in the window and in Teams on winpc.
- Find in post uses OST's find bar for now; Teams' find pane is TASK-0051 AC3.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A channel post's conversation opens in a window of its own (Teams' "Open conversation in new window"), laid out as Teams' pop-out. It stays live and bound to its thread whatever the main window shows.

Changes:
- Backend:
  - thread windows load the reply chain (`{channel};messageid={post}`) and reload on pushes for their channel;
  - `send_thread_reply` and `send_thread_files` reply into the thread;
  - message actions route to the conversation that shows the message (`chat_of`): reactions, edit, delete, save, pin, translate, forward, mark unread, follow.
- MessageHost.qml: Conversation's menus, reaction picker, who reacted, fun picker, Forward/Report and edit state, now reusable. Conversation and the thread window each have one.
- ThreadWindow.qml (measured on winpc):
  - header, More channel options (Find in post, Follow/Unfollow thread);
  - the post and replies card, day dividers, hover bars;
  - "Reply in thread" compose.
- MessageText.qml is shared with ChannelPosts.
- Team pictures in headers use Teams' 2 px corners.

Tests:
- `--thread-window-test`, live in OST Test Team: reply, Like and edit from the window while the main window shows another chat; all three show in Teams on winpc.
- `--thread-window-view`: layout, the reply hover bar, and the post menu item.
- `--actions-test` and `--who-reacted-test` pass (no regressions from the MessageHost refactor).
- lib tests: 365 passed.

Follow-up: Teams' find pane for Find in post (TASK-0051 AC3).
<!-- SECTION:FINAL_SUMMARY:END -->
