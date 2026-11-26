---
id: TASK-0306
title: Hiding many chats rebuilds the chat list for each one
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T18:10:00Z'
updated_date: '2026-11-26T03:42:00Z'
labels:
  - bug
  - chat
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while staging wiki demo data: hiding many chats in a row makes OST rebuild the whole chat list for every chat; its memory grew to about 13 GB before the instance was stopped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Hiding or unhiding many chats (including a few hundred in a row, as when other clients hide them) updates the chat list without rebuilding it per chat, with no memory growth
- [x] #2 OST's memory stays flat while chat-list updates arrive in bursts (live check on linuxlt)
- [x] #3 A chat hidden or shown by another client is not marked unread by that update
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Trace the path: Trouter push -> event_hub::conversation_ids -> Backend::on_chat_push -> publish_chats/reload_chats -> chats_json -> QML ChatList (Flickable/Column/Repeater over JS arrays).
2. Backend: coalesce push-driven reloads (quiet period + max wait) and stop conversation/thread updates (hide/unhide pushes) from marking chats unread, which also published the list once per push.
3. QML: keep ChatList sections and rows as keyed ListModels synced in place, so an update only touches changed rows; parse member counts once; Conversation reads its chat entry once per update.
4. Add a --chatlist-churn-test harness; measure RSS on linuxlt before/after (main QML vs fixed QML via OST_QML_DIR), then a live burst of real hides/unhides on a test account.
5. Unit tests for the push filtering; CI fmt/clippy/tests on linuxlt.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: ChatList was a Repeater over JS arrays, so every chatsJson change destroyed and rebuilt every row; each row also built a menu, a flyout and three dialogs. With ~180 chats one update took tens of seconds of main-thread time, and the rows waiting for deleteLater piled up. On top of that, every hide push caused a reload, and conversation updates marked chats unread, which published the list again.
- Fix: keyed ListModels synced in place, popups created lazily, push reloads debounced (400 ms quiet, 2 s max), unread set only by new messages from others, older chat-list slices kept current from the first page (bursts brought hidden chats back or dropped chats).
- linuxlt, ost-test1 (spatest), 176 real hides and then unhides through the chat service, 300 ms apart. main: 3.1 GB rising to 8.09 GB (stopped by the 8 GB cap), list frozen. Fix: flat at 2.14 GB, list follows each hide and unhide (shown 178 -> 1 -> 175), unread stays 0.
- Churn harness (400 updates, no server writes): main QML 3.5 GB, under 50 updates done in 5 min; fix flat at 2.15 GB, 400 updates in ~45 s.
- PR #4 (RandyNorthrup/ost): CI green, Codex found nothing.

- Codex review (PR #4): when another device marks a chat unread, that arrives as a property update, which no longer marked anything. Chats whose properties a push changed now get their unread state read back from the chat service once the pushes settle (check_unread).
- After PR #7, profiles signed in before it fall back to the sign-in screen at startup (the silent renewal needs a web session the new per-profile web storage lacks), so the last live run on the rebased test-harness build could not list chats. The verified runs used the pre-rebase builds.

- Codex review 2 (PR #4): a read-back answer older than a newer push or local mark could clear a just-unread chat. The unread set is now UnreadChats, with a change count per chat; read-back answers apply only to chats unchanged since the request went out. Unit tests cover the race.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Hiding hundreds of chats in a row no longer rebuilds the chat list per update or grows memory (PR #4, RandyNorthrup/ost).

Cause:
- ChatList drew its sections with a Repeater over JS arrays, so every chatsJson change destroyed and rebuilt every row. Each row also built a menu, a notification flyout and three dialogs.
- With ~180 chats one update took tens of seconds of main-thread time, and the destroyed rows piled up waiting for deleteLater.
- Every push caused a reload, and conversation updates (each Hide pushes two) marked chats unread, which published the list again.

Changes:
- ChatList: sections and rows are keyed ListModels synced in place. Unchanged rows keep their items, a hidden or shown chat removes or adds one row, and menus and dialogs are created on first use. Member counts are parsed once; Conversation parses the chat list once instead of five times.
- Backend: push-driven reloads are debounced (400 ms quiet, 2 s max). Only new messages from others mark a chat unread; after property pushes, unread state is read back from the chat service (check_unread).
- api::chat: the cached older slices of the list are updated from the first page on every read, so bursts no longer bring hidden chats back or drop chats.
- Harness flags --chatlist-churn-test=<n> and --chatlist-watch, documented in docs/desktop.md.

Tests:
- Unit tests for unread_conversation_ids and refresh_older. CI is green: fmt, clippy, build and test, CodeQL.
- Live on linuxlt (ost-test1, 176 real hides then unhides): main went 3.1 to 8.09 GB (stopped by the cap) with a frozen list. The fix stayed flat at 2.14 GB and the list followed every change (shown 178 -> 1 -> 175, unread 0).
- Churn harness (400 updates): main QML 3.5 GB, under 50 updates done in 5 min; fix flat at 2.15 GB.

- The unread read-back tracks a change count per chat (UnreadChats) and never undoes a newer push or local mark; unit tests cover the race.
<!-- SECTION:FINAL_SUMMARY:END -->
