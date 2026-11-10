---
id: TASK-0042
title: >-
  Message timeline data as Teams: history paging, all message types, send
  states, soft delete
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-10T17:18:00Z'
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
- [x] #3 Delete is Teams' soft delete with the tombstone and Undo
- [x] #4 Read receipts: Teams' Seen rule (at most two icons, 2-20 members); typing indicator with Teams' timeouts and multiple typers
- [x] #5 Optimistic send as Teams' pipeline: Sending/Retrying/failed states, transport retries and offline queue replays, Teams' failure texts, Retry and Delete
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- History paging researched in Teams' worker (module `ne`: v1/users/ME/conversations/{id}/messages?view=msnp24Equivalent[|supportsMessageProperties]&pageSize=200[&syncState=…]&startTime=1; older page = syncState of _metadata.backwardLink; cap 200).
- Built: read_timeline_page / backward_token / merge_pages; backend keeps each chat's older pages + token, merges into refreshes; loadOlderMessages at the top keeps the top message in place.
- Verified against the live service: OST group test paged 3 at a time back to the start = the full history, no duplicates.

- System/control messages: researched module 75579 (strings, AddMember parsing, missed-call rule) and 349533 (type→icon table); live rows measured on winpc (28/36 px rows, icon x6 y8, text 12px x40 y10, names regular, call duration bold).
- Built: chat_event/event_text (AddMember incl. history and self-join, DeleteMember self/by/system, TopicUpdate incl. removed/meeting, PictureUpdate, MemberJoined, MemberLeft, MemberRenamed) with names from the event or Graph (cached); rows drawn as Teams with its icons; call rows with Teams' {h}h {m}m {s}s bold duration. Remaining types for AC2: cards, contacts, media, polls, recordings/transcripts.

- Soft delete: Teams' deleteMessage = DELETE …/messages/{id}?behavior=softDelete; undo = DELETE …/messages/{id}/properties?name=deletetime; canBeUndeleted is client-side (deleted this session). Tombstone measured on winpc (own bubble, italic #242424 14px, "Undo" 14px semibold #4F52B2 12px after). Built and verified with --delete-undo-test on ost-test1's notes chat (delete → tombstone → Undo → restored).

- Seen: Teams' rule (module 434910): min of the other members' horizons, max messageVisibilityTime, 2-20 members (roster size remembered from consumptionhorizons); at most two icons (sent tick on the newest own message, eye on the newest seen). Live: eye on test 26 (1:1) and test 27 (group) matches winpc.
- Typing: 22 s per typer, 3 s linger, 1/2/3/N wordings, typers keyed by MRI, names resolved from the MRI (group events carry no imdisplayname), a typer's own message removes only them, cleared on chat switch, hidden in channels and above 20 members. Layout from Teams web: avatar (photo) tucked under the compose box, label only in group chats (1:1 is avatar-only), dots.
- Live: Randy's Teams web typing showed in OST, expired at 22+3 s, and cleared 3.0 s after his message arrived.
- Fixed: positional harness args (<shot> <send text> <await text>) no longer pick up --flags; a run with only flags had sent a flag as a message (deleted with Teams' Delete on winpc).

- Send pipeline from docs/spec/send-pipeline.md (researched from the client code): src/api/outbox.rs implements the lie (clientmessageid, arrival max(now, last+1)), Teams' POST body, transport retries (5 attempts, 1/2/4/8 s, Retry-After, 401 once, 502/503 3x), error classification and sendPipelineStatus texts, and the per-conversation offline queue persisted to $XDG_STATE_HOME/ost/outbox.json (replay at startup, on Trouter connect and every 10 min; 10 cross-session retries; 48 h expiry; dedupe before replay).
- Live tests: (1) a real send showed Sending at +57 ms and Delivered at +580 ms, and the lie was replaced by the server copy. (2) A send to a missing conversation gave a 404, Teams' "Message didn't send..." text, a red bubble, a red warning icon, and Retry and Delete; Delete removed it locally. (3) With the chat service cut by a local proxy, the transport tried for 15 s, then the message went to Retrying with the connection tooltip and was persisted. After a restart the replay delivered it, and Randy's web shows it once.
- Still to do: the "Report a problem" link that Teams adds to the 404 text.

- AC2 (cards): card messages parse (Media_Card SWIFT b64 / JSON fallback, properties.cards) and Adaptive Cards render natively with Teams' host config and frame (measured against the desktop client). Left: hero / thumbnail / list / O365 connector cards, Action.Submit / Execute bot invokes and the result footer, carousels, AMS-authenticated images.

- 2026-11-10: meeting recordings render as Teams' control rows (started, stopped, saved with "Remove expiration"). Transcript-only rows and legacy Media_CallTranscript are hidden outside 1:1, and Media_MeetingObjects is never shown (this was the raw {"scopeId"…} JSON). Meeting chats' call rows read "Meeting ended: {duration}" with the video icon. Verified side by side in OST calendar test.
<!-- SECTION:NOTES:END -->
