---
id: TASK-0163
title: 'Chat list: chats with no messages as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T23:27:00Z'
updated_date: '2026-11-16T02:42:00Z'
labels:
  - desktop
  - chat-list
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A group chat created with members but no messages (OST large chat test, made through the chat service on 2026-11-15) was not in Teams' chat list on winpc even after a restart; it appeared once OST TEST 160 was sent. OST listed it straight away. Find Teams' rule for listing chats that have no messages yet and match it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Teams' rule for when a chat with no messages is listed is found in its code and checked on winpc
- [x] #2 OST's chat list follows the same rule
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-15: the first observation was wrong. Teams does list chats nothing has been said in: "OST empty chat test" (made empty through the chat service) and the empty Meet now chats are in its list on winpc. The large chat was likely missed because Teams had been restarted just before it was made.
  - From the chat service and Teams' list: Teams leaves out empty one-on-ones, lobby chats (threadSubType LobbyChat), breakout room chats (meeting threads with no meetingChatPolicy), and chats without memberProperties.interest "Interested" (left, or only in the lobby).
  - Teams orders by activity (last message, or lastjoinat for an empty chat), not the service's order.
  - OST now does both (api::chat unlisted and activity_ms), and its list matches Teams' (the same 13 chats in the same order).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's chat list now lists the same chats as Teams, in Teams' order.

Changes:
- Chats nothing has been said in are listed (OST used to hide them).
- api::chat::unlisted leaves out what Teams leaves out: empty one-on-ones, lobby chats, breakout room chats, and chats you aren't an interested member of.
- Chats sort by activity (last message, or when you joined an empty chat), as Teams' Most recent.

Tests:
- 555 library tests pass, including the new unlisted test.
- OST's list compared with Teams' on winpc: the same 13 chats in the same order.
<!-- SECTION:FINAL_SUMMARY:END -->
