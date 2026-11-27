---
id: TASK-0351
title: >-
  OST reads hundreds of meeting threads whenever it reads the chat list,
  throttling its own chat reads
status: In Progress
assignee:
  - '@chatreads'
created_date: '2026-11-27T14:32:00Z'
updated_date: '2026-11-27T17:16:00Z'
labels:
  - chat
  - bug
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0350's live checks (2026-11-27): each chat-list read makes OST (api::chat::meeting_backroom) GET /v1/threads/{id}?view=msnp24Equivalent for every titled meeting chat it hasn't classified (~220 for OST Test 1, up to 180 per second). The chat service's per-user quota (429 'API calls quota exceeded! 20Per10SecswithDepth6', Retry-After 0) then refuses most of them, and since a refused read isn't remembered the next chat-list read (start-up, a new chat appearing) asks for all of them again. Every other thread read in that window fails too: opening a chat, a call's members, the activity feed. Teams doesn't read meeting threads in bulk.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reading the chat list doesn't cause the chat service to throttle OST's thread reads (no burst of meeting-thread reads), while backroom/event chats are still named as Teams names them, verified live as OST Test 1
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Name backroom/event chats from Teams' CSA chat sync (startupclean once, startupdelta with x-ms-synctoken for new chats, paced, refusals remembered) instead of reading every titled meeting chat's thread (api::chat_sync).
2. Unit tests for parsing, pacing and backoff; spec in chat-list-and-header.md.
3. Live as OST Test 1 on linuxlt: no burst of /v1/threads/19:meeting_ reads and no 429s from the chat list; backroom chats still titled Event group / Planning group as Teams titles them.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (bundles 26304 on testpc1, read from its Service Worker cache): csaService endpoints startupclean teams/users/me, startupdelta teams/users/me/updates (header x-ms-synctoken), startupgroupchats, startupnonrecentchats (?skipNonRecentMeeting=&pageSize=). No bulk thread reads for chat kinds.
- CSA v3 clean sync as ost-test1 (2026-11-27): 269 chats, metadata {hasMoreChats: true, isPartialData: true, syncToken}; 238 meeting chats, 7 meetingChatType backroom (templateDetails.id firstparty_21f9… = town hall), 3 lobby. The chat service's own list has no meetingChatType at all.
- Of the 262 listed titled meeting chats in the chat service list, 196 are in the clean sync; the 66 left out: 63 thread reads (slow, 1/s) said none is a backroom, 4 throttled. nonrecentchats?skipNonRecentMeeting=false added 1 chat; so OST doesn't read it.
- Takeover fix: the first draft re-synced every minute while any listed meeting chat was missing from the sync (66 for ost-test1), and on every list read if a clean sync named no token. Now a chat a sync was asked about isn't asked about again (SyncState.asked), and any sync waits a minute after the last.
<!-- SECTION:NOTES:END -->
