---
id: TASK-0254
title: Chat fixes from the release screenshot pass
status: Done
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T17:39:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bugs seen while taking the 0.2.0 screenshots (OST Test 2/3 on linuxlt). Each must behave as Teams desktop does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An empty unnamed group chat shows Teams' generated name (its members) in the chat list, never the raw 19:…@thread.v2 id
- [x] #2 A chat opened from Activity or the chat list after viewing a channel or post shows only the chat's own header tabs
- [x] #3 Starting a brand-new 1:1 chat and sending the first message works as in Teams (no 404 CONVERSATION_DELETED), and a failed message is never left in another profile's outbox (outbox is per profile)
- [x] #4 A new group chat shows in every member's chat list as Teams lists it, without the member opening it first
- [x] #5 The Like reaction shows Teams' thumbs-up emoji everywhere reactions appear
- [x] #6 Unsent drafts are kept per profile too (both sides of a 1:1 share its id, so one account's draft never shows in another's compose box)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (fixV) What Teams does:
  - Unnamed group chat names: worker 98382/99234: members sorted by name, the first three others by short (given) name, joined with ", " up to 24 chars, as an Intl list when all fit in 26, ", +N" for the rest (N = left out + 1); "Just me" / "Unknown". Teams on winpc (ost-test1) lists the Test 1/2/3 empty group chats as "OST and OST Test 3".
  - Chat list membership (worker 3398 `sn`): a chat is left when lastleaveat > lastjoinat; `interest` is not used (OST Test 3 has no interest on "OST 0.2.0 release" even after reading it), so OST's interest rule hid new group chats.
  - New 1:1: Teams creates the thread first (createThread: threadType chat, fixedRoster, uniquerosterthread, chatFilesIndexId 2) and then sends; OST sent to the not-yet-existing 19:a_b@unq.gbl.spaces (404 CONVERSATION_DELETED).
  - Like: Teams' Like reaction is the client emoticon "yes" (service key "like"); client "like" (service "likeWithFaceMSER") is the face-with-thumbs-up emoticon. The release tour called toggleReaction(id, "like"), which Teams would also store as likeWithFaceMSER. Activity shows the emoticon image (20 px in a 24 px pane-coloured circle, +18/+14 from the picture).
  - Posts/Shared in a chat: a channel tab load fired while the conversation switched from a channel to a chat (isChannel still true for a moment) and its channel tabs were then shown as the chat's own tabs.

- Verified live on linuxlt (ost-fixV, local tour harness, not committed):
  - Test 3: the five empty Test 1/2/3 group chats are named "OST and OST", Test 2 sees "OST and OST Test 3" (Teams on winpc shows Test 1 the same pattern: "OST and OST Test 3"). No 19:… names left. "OST 0.2.0 release" and "OST 0.2.0 demo call" (no interest) are listed.
  - Channel (OST test channel) then chat (OST 0.2.0 release), and channel 2 > Activity > chat: tabs Chat, Shared, Notes, Recap only.
  - Test 2 openChatWith(Test 3): the first send got 404, OST created the 1:1 (createThread) and the message arrived ("created the new 1:1 chat for its first message"); the chat lists for both. Outbox/drafts now outbox-test2.json / drafts-test2.json. Teams hides AddMember in 1:1s (getCtrlMsgFilter), so OST now does too.
  - Like: Test 3 reacted with "yes" (Teams' Like): thumbs-up pill for both; Test 2's Activity shows the thumbs-up emoticon badge, the release tour's earlier client "like" reactions show Teams' face-with-thumbs-up (as Teams draws likeWithFaceMSER).
  - Startup 429s on the per-chat member reads: retried after a pause (names were "Unknown" on the first load without it).
- Cleanup: removed the stray Test 3 failed message from linuxlt's shared outbox.json (backup ~/fixV_w/outbox.json.bak); deleted my test message in the Test 2/Test 3 1:1 (the 1:1 itself stays, empty).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat fixes from the 0.2.0 screenshot pass, each as Teams does it.

Changes:
- Unnamed group chats get Teams' generated name (api::chat::generated_title, worker 98382/99234): first three others by short name, 24/26-character fit, list format, ", +N", "Just me"/"Unknown"; members (cached by roster version) and short profiles (cached an hour) are read with a retry for startup throttling. Never the thread id.
- Chat list membership: Teams' rule (left = lastleaveat after lastjoinat) replaces the `interest` rule, so chats you were added to are listed without opening them.
- Header tabs: a channel's tab load is only made for a channel id and its JSON carries kind channel/chat; a chat never shows a channel's Posts/Shared.
- New 1:1: on 404 for a 19:a_b@unq.gbl.spaces chat the outbox creates it as Teams does (ensure_one_on_one_chat) and sends again; Teams' AddMember lines are hidden in 1:1s.
- Outbox and drafts are per profile (outbox-<profile>.json, drafts-<profile>.json; the first account keeps the old names).
- Activity reactions show Teams' emoticon (client id, so the service's like is the thumbs-up "yes") in Teams' 24 px badge.

Tests: cargo test --features audio,video --lib (933 passed) and the desktop crate (36 passed) on linuxlt; new unit tests for names, membership, 1:1 creation, AddMember and per-profile paths. Live checks on linuxlt as OST Test 2 and 3 (notes).

Note: the "face" Like in the release screenshots came from the tour calling toggleReaction(id, "like"); Teams' Like is "yes".
<!-- SECTION:FINAL_SUMMARY:END -->
