---
id: TASK-0082
title: Threads channel layout as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T18:48:00Z'
updated_date: '2026-11-11T23:55:00Z'
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
- [x] #4 A channel converted from Posts shows Teams' 'A channel owner set this channel to a threads layout' banner
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

- 2026-11-11: converted-channel banner. Teams' ThreadedChannelInfoBanner (channels:threaded_channel_learn_more) shows in a threads channel's main view until dismissed (local setting) or until ESP action ThreadedChannelInteraction is recorded (PUT {mt}/beta/me/engagementSurfaces/actions, sent on a main-view send). New src/api/engagement.rs reads/records ESP actions.
- CSA teams list omits modality for OST Test 2; layout now read from the thread (GET /v1/threads/{id} properties.chatModalityType) on open and kept.
- ThreadActivity/ModalityUpdate renders "The layout was changed to threads." / "… to posts." with the pencil icon. Verified as OST Test 2 in "OST layout test" (converted by Teams on winpc). Commit 88a472a.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channels in Teams' Threads layout now look and behave as Teams shows them.

Changes:
- Conversation view for threads channels: chat bubbles, reply counts, hover "Reply in thread", "Replied in thread" / "Also sent to channel" lines, the "Message in <channel>" compose.
- ThreadsPane: thread list and single-thread view, Send to (thread only / thread and channel), Open threads toggle, header actions.
- Unread threads from rcmetadata ch/chb: bold reply counts and the pane's Last read line; opening a thread marks it read.
- Converted channels show Teams' "A channel owner set this channel to a threads layout. Learn how threads work" banner, dismissed locally or by the ESP action ThreadedChannelInteraction (new src/api/engagement.rs).
- A channel's layout is read from its thread properties when the teams list omits it; ModalityUpdate events render as Teams' "The layout was changed to threads/posts."

Tests:
- cargo test --lib (449 pass), including ModalityUpdate and conversation facts parsing.
- Verified side by side with Teams on winpc in "OST threads test" and "OST layout test" (OST Test 1 and OST Test 2).
<!-- SECTION:FINAL_SUMMARY:END -->
