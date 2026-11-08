---
id: TASK-0056
title: Live roster of a call you aren't in (chat header avatars)
status: Done
assignee: []
created_date: '2026-11-08T04:07:00Z'
updated_date: '2026-11-08T17:05:00Z'
labels:
  - calls
  - chat
dependencies: []
references:
  - desktop/qml/Conversation.qml
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' chat header shows who is in a live meeting or group call (participants-live-roster-list: 32 px avatars overlapping by 10, up to 5 then +N) even when you haven't joined. OST only knows who started the call (the thread's liveness entry), so the meeting chat's live band and the group-call pill show no or one avatar. Needs research into how Teams gets that roster for an unjoined call.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A live meeting's chat header shows the avatars of the people in the meeting, as Teams does, without joining
- [x] #2 A group chat's call pill shows everyone in the call, not just who started it
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat headers show who is in a call you haven't joined, as Teams does.

- Teams subscribes to the call's conversation without joining (subscribeToCall: a conversation request with no call to the liveness conversationUrl). OST does the same in calling::live_roster, with callbacks under subscription/… so the roster never mixes with a call you're in; it follows roster deltas and leaves when the chat changes.
- Group call pill: everyone in the call (was: only who started it). Meeting live band: Teams' chat-live-roster as measured on winpc (32 px avatars 22 apart, 7 after the duration, 8 before Join, max 5 then +N, from 834 wide). Both leave you out.

Verified live: meeting with two guests (and one leaving), Meet now from Teams web, leave on chat switch (204).
<!-- SECTION:FINAL_SUMMARY:END -->
