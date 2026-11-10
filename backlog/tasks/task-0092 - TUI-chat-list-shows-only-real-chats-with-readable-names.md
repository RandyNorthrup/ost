---
id: TASK-0092
title: TUI chat list shows only real chats, with readable names
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:39:00Z'
updated_date: '2026-11-10T15:44:00Z'
labels:
  - tui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The TUI's chat list includes the account's system streams (48:drafts, 48:threads, 48:notifications, 48:calllogs, 48:saved, 48:mentions) as chats, some named only by their id; opening 48:drafts fails with HTTP 400. Several real chats also show as raw thread ids (19:Ikvn…, 19:ldSo…, 19:4287e791…) instead of their names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 System streams (48:*) are not listed as chats, except the notes-to-self chat, which shows as '<name> (You)'
- [x] #2 Every listed chat shows a readable name (topic, or the other members' names) instead of a raw id
- [x] #3 Opening any listed chat loads its messages without an error
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TUI chat list now shows the chats Teams shows, by the same rules as the desktop:
- your notes-to-self chat first, as "{you} (You)";
- no system streams (48:drafts, 48:threads, 48:notifications, 48:calllogs, 48:saved, 48:mentions);
- no channels (they're listed under their team);
- no empty or hidden chats.

The raw-id entries (19:Ikvn…, 19:ldSo…, 19:4287e791…) were empty chats, so they're gone too.

Changes:
- New `api::listed_chats` / `api::notes_name` (src/api/chat.rs), used by the TUI when chats load. The notes chat is renamed once the user's name arrives.
- `ChatInfo` derives Default (for tests).

Tests:
- New `chats_are_listed_as_teams_lists_them`.
- Live in tmux: the list shows OST Test 1 (You), OST group test, Randy Northrup and OST calendar test; each opened without an error (opening is GET-only).
<!-- SECTION:FINAL_SUMMARY:END -->
