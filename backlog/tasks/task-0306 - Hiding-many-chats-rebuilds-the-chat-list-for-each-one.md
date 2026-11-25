---
id: TASK-0306
title: Hiding many chats rebuilds the chat list for each one
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T18:10:00Z'
updated_date: '2026-11-25T21:25:00Z'
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
- [ ] #1 Hiding or unhiding many chats (including a few hundred in a row, as when other clients hide them) updates the chat list without rebuilding it per chat, with no memory growth
- [ ] #2 OST's memory stays flat while chat-list updates arrive in bursts (live check on linuxlt)
- [ ] #3 A chat hidden or shown by another client is not marked unread by that update
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Trace the path: Trouter push -> event_hub::conversation_ids -> Backend::on_chat_push -> publish_chats/reload_chats -> chats_json -> QML ChatList (Flickable/Column/Repeater over JS arrays).
2. Backend: coalesce push-driven reloads (quiet period + max wait) and stop conversation/thread updates (hide/unhide pushes) from marking chats unread, which also published the list once per push.
3. QML: keep ChatList sections and rows as keyed ListModels synced in place, so an update only touches changed rows; parse member counts once; Conversation reads its chat entry once per update.
4. Add a --chatlist-churn-test harness; measure RSS on linuxlt before/after (main QML vs fixed QML via OST_QML_DIR), then a live burst of real hides/unhides on a test account.
5. Unit tests for the push filtering; CI fmt/clippy/tests on linuxlt.
<!-- SECTION:PLAN:END -->
