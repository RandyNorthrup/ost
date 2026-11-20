---
id: TASK-0229
title: 'TUI: live messages and unread counts'
status: Done
assignee: []
created_date: '2026-11-20T01:21:00Z'
updated_date: '2026-11-20T21:06:00Z'
labels:
  - tui
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from TASK-0002, which was marked Done with these two criteria never met: the terminal client has no live push (no trouter connection) and its sidebar unread counts are always 0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Incoming messages appear in the TUI in real time via Teams' push (trouter), as in the desktop app
- [x] #2 Unread counts on channels and chats in the TUI sidebar reflect the real unread state
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (agent tuiF): Teams' rule (bundles 26304): a chat row is bold when unread (consumption horizon behind someone else's last text message, or marked unread) and gets a dot when it counts toward the badge (unread and not muted); Teams has no per-chat number (its unreadMessageCount is a fixed 50/100 placeholder); channels are bold when unread (CSA isMessageRead false); a team row is bold only while collapsed with an unread channel; the Chat badge = unread unmuted chats.
- Built: TUI backend connects Trouter (ListenOptions::EMBEDDED, as the desktop) and forwards chat pushes; the open conversation reloads in place (keeps your place, follows new messages at the bottom), other conversations with someone else's new message turn unread, chat/team lists reload (folded while one runs); opening a chat/channel marks it read (consumption horizon), only while the terminal has focus (focus reports); chat list unread from messages::is_unread, channels from Teams' CSA team list (shown channels, isCollapsed); sidebar: bold + dot, CHATS (N) header = unread unmuted chats, selection kept by id across reloads.
- Verified live (TUI on this PC as ost-test1, tmux; OST Test 3 posted with examples/post_text): post 1 while another chat was open -> OST Test 3 chat appeared at the top, bold with a dot, CHATS (1); opening it cleared the dot and moved the server horizon to the message; post 2 appeared live in the open chat and stayed read (horizon = it); a channel post made OST test channel bold, its collapsed team bold; opening it marked it read (CSA isMessageRead true). Deletions showed live too. Test posts deleted.

- 2026-11-20 merged as 42c9597; 825 lib + 29 desktop tests pass on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TUI live messages and unread state as Teams.

- The TUI connects to Teams' push service (Trouter) as the desktop app does; the open chat updates in place keeping the scroll position, other chats turn unread on others' posts and the lists reload in Teams' order.
- Unread comes from the server (chat read horizons, Teams' team list for channels); opening a chat or channel marks it read only while the terminal has focus. Chats are bold with a dot unless muted, channels bold, a collapsed team bold with an unread channel; the CHATS header shows (N) unmuted unread chats, as Teams' Chat badge counts.

Verified live in tmux as ost-test1 with OST Test 3 posting (posts deleted).
<!-- SECTION:FINAL_SUMMARY:END -->
