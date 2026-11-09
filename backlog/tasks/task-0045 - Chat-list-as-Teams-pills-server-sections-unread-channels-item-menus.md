---
id: TASK-0045
title: 'Chat list as Teams: pills, server sections, unread channels, item menus'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-09T12:33:00Z'
labels:
  - desktop
  - chatlist
dependencies: []
references:
  - docs/spec/chat-list-and-header.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Chat list gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/chat-list-and-header.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Filter pills Unread, Channels, Chats, Meeting chats (+Communities when licensed) with Teams' combination and overflow rules
- [x] #2 Sections, their order and expansion come from the server (conversationFolders), incl. custom sections
- [x] #3 Only shown channels are listed; channel and team unread state as Teams
- [x] #4 Chat item ··· and right-click menu as Teams for Mark read/unread, Move to section ▸ (Favorites, your sections, New section), Remove from section, Mute, Copy link, Leave (≥ 3 members, not a meeting chat you created) and Hide/Unhide; the rest of Teams' chat menu is TASK-0075
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research:
   - conversationFolders (read, and the write actions from Teams' worker);
   - section visibility (prod flags);
   - the CSA team list (shown/unread/New);
   - live pills, overflow and the empty state;
   - live chat menus, with Hide/Unhide captured on OST group test (scratchpad cl/notes.md).
2. api::folders (read, expand, create, rename, delete, move/remove item) and api::teams::list_teams_csa; chat hidden/creator flags; hide and leave calls.
3. Backend: folders_json, folder_action, set_chat_hidden, leave_chat, member counts.
4. ChatList.qml rebuilt on the server sections: pills with overflow, team/channel state, the chat menu with Move to section; SectionDialog.
5. Live harness --chatlist-test; follow-up TASK-0075.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Verified on linuxlt (--chatlist-test):
  - the server's sections in order;
  - pills (Unread / Channels / Chats / Meeting chats; Communities in the second row; More filters);
  - a new section "OST test section" holding OST group test (and gone from Chats), renamed, collapsed (saved on the server), then removed;
  - OST group test hidden and unhidden.
- User sections come back as folderType UserCreated. An early run sent the kind as the name on collapse; fixed, and the harness cleans such leftovers.
- Teams writes Hide as conversation properties unpinnedTime + historyHiddenTime, and Unhide as both null (captured on winpc).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The chat list now follows Teams: sections and their state come from the server, with Teams' filter pills, shown channels only, and more of the chat menu.

Changes:
- `api::folders` reads Teams' conversation folders and makes Teams' folder writes: expand/collapse (one or all), create (optionally moving a chat into it), rename, delete, move/remove item.
- `api::teams::list_teams_csa` reads Teams' CSA team list: shown channels (isFavorite), unread, muted, General, New (no read horizon), and each team's collapsed state.
- Chats carry `hidden` (Teams' historyHiddenTime, until a newer message) and `isCreator`. New calls: Hide/Unhide (unpinnedTime + historyHiddenTime, null to unhide, captured from Teams) and Leave (`DELETE v1/threads/{id}/members/{mri}`).
- `ChatList.qml` is rebuilt:
  - the server's sections in order with saved expansion, including your own sections (with their ··· menu, Rename/Remove, and `SectionDialog`);
  - Teams' pills (Unread combinable, single-select categories, overflow to a second row behind More filters, the chosen pill kept visible) and "You're all caught up!";
  - only shown channels; unread in bold (teams only while collapsed); the "New" badge;
  - the chat menu: Mark as read/unread, Move to section ▸ (Favorites, your sections, New section), Remove from section, Mute, Copy link, Leave (≥ 3 members, not a meeting chat you created), Hide/Unhide.
- Ctrl+Alt+B (Meeting chats) and Ctrl+Alt+Z (clear filters). Communities ▸ Join communities opens Viva Engage as Teams embeds it.
- Docs: docs/spec/chat-list-and-header.md §3.0a and the status list.

Tests:
- `cargo test --lib folders`, `list_tests` and the chat tests.
- Live on linuxlt (`--chatlist-test`), all on ost-test1's own data:
  - pills, sections and the menu;
  - a section created with OST group test, renamed, collapsed (saved) and removed;
  - OST group test hidden and unhidden.
- Not tried live: Leave (there's no disposable chat with 3+ members).

Follow-up: TASK-0075 (the rest of Teams' chat menu, Followed threads and Saved quick views, the Copilot row, team order).
<!-- SECTION:FINAL_SUMMARY:END -->
