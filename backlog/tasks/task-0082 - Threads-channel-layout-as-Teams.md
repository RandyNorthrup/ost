---
id: TASK-0082
title: Threads channel layout as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T18:48:00Z'
updated_date: '2026-11-10T13:23:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Channels can use Teams' Threads layout (chatModalityType Conversational): the channel shows as a chat with a Conversation tab, chat bubbles, Start a thread on posts, replies in a side thread pane, the 'A channel owner set this channel to a threads layout' banner and a 'Message in <channel>' compose (seen on winpc, 2026-11-09). OST only renders the Posts layout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Threads open in Teams' side thread pane, with replies
- [x] #2 Verified side by side with Teams on winpc
- [x] #3 A Threads-layout channel shows as Teams shows it (Conversation tab, chat bubbles, reply counts, Reply in thread, replies also sent to the channel, Open threads, the 'Message in <channel>' compose)
- [ ] #4 A channel converted from Posts shows Teams' 'A channel owner set this channel to a threads layout' banner
- [x] #5 Unread threads show as Teams shows them (bold reply count, the pane's Last read line, from rcmetadata ch/chb)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' Threads layout on winpc (channel, pane, list, Send to, shared replies, service calls)
2. Conversation: threads layout (bubbles, reply line, hover Reply in thread, shared-reply lines)
3. ThreadsPane: list + thread, header actions, Send to compose
4. Backend: isSharedInMain send/read, threads root body, rcmetadata read/unread, push reload
5. Verify side by side, spec, tests
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10: built the Conversation view, threads pane (list + thread), Send to (thread only / thread and channel), Replied in thread / Also sent to channel, Open threads toggle, ··· menu for Threads channels, rcmetadata ch/chb, push reload for thread replies. Verified against Teams with OST TEST 81-86 in "OST threads test".
- Teams' hover label is "Reply in thread" on every message (no "Start a thread" seen).
- Left: converted-channel banner (needs a channel converted from Posts), unread thread state, the narrow-header "Conversation ⌄" tab menu.

- Unread threads: rcmetadata ch/chb read per thread; bold reply count, Last read line in the pane, chb:0 on opening (captured from Teams). Verified Mark as unread from OST and reopening.
<!-- SECTION:NOTES:END -->
