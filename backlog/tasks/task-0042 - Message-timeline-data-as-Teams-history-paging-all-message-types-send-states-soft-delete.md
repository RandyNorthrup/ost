---
id: TASK-0042
title: >-
  Message timeline data as Teams: history paging, all message types, send
  states, soft delete
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T04:50:00Z'
labels:
  - desktop
  - messages
dependencies: []
references:
  - docs/spec/messages-and-composer.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Timeline data gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/messages-and-composer.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Older messages load on scroll-up (Teams' paging)
- [ ] #2 Every message type Teams shows per chat kind renders (system/control events incl. member added and rename, call rows with bold duration, cards, files, media)
- [ ] #3 Optimistic send with Sending/Retrying/failed states and Retry/Edit/Delete
- [ ] #4 Delete is Teams' soft delete with the tombstone and Undo
- [ ] #5 Read receipts: Teams' Seen rule (at most two icons, 2-20 members); typing indicator with Teams' timeouts and multiple typers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- History paging researched in Teams' worker (module `ne`: v1/users/ME/conversations/{id}/messages?view=msnp24Equivalent[|supportsMessageProperties]&pageSize=200[&syncState=…]&startTime=1; older page = syncState of _metadata.backwardLink; cap 200).
- Built: read_timeline_page / backward_token / merge_pages; backend keeps each chat's older pages + token, merges into refreshes; loadOlderMessages at the top keeps the top message in place.
- Verified against the live service: OST group test paged 3 at a time back to the start = the full history, no duplicates.

- System/control messages: researched module 75579 (strings, AddMember parsing, missed-call rule) and 349533 (type→icon table); live rows measured on winpc (28/36 px rows, icon x6 y8, text 12px x40 y10, names regular, call duration bold).
- Built: chat_event/event_text (AddMember incl. history and self-join, DeleteMember self/by/system, TopicUpdate incl. removed/meeting, PictureUpdate, MemberJoined, MemberLeft, MemberRenamed) with names from the event or Graph (cached); rows drawn as Teams with its icons; call rows with Teams' {h}h {m}m {s}s bold duration. Remaining types for AC2: cards, contacts, media, polls, recordings/transcripts.
<!-- SECTION:NOTES:END -->
