---
id: TASK-0090
title: >-
  Act on synced chat settings as Teams: compact density, chat landing,
  auto-follow, suggested replies
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T10:14:00Z'
updated_date: '2026-11-14T03:05:00Z'
labels:
  - desktop
  - settings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings ▸ Chats and channels now saves these where Teams does (TASK-0088), but OST doesn't yet behave by them: Compact message density (Teams' compact message layout), When I open a chat take me to Last read / Newest message (with the new-messages divider), automatically following channel threads you start, reply to or are @mentioned in, and suggested replies in chat.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Compact density lays out messages as Teams' compact mode
- [x] #2 Opening a chat lands on the last read message or the newest, as chosen, with Teams' new messages divider
- [x] #3 Threads you start, reply to or are @mentioned in are followed as the auto-follow choices say
- [x] #4 Suggested replies show in chats as Teams' when on
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Chat landing done: opens on the Last read line (or newest, per setting); read position honours consumptionHorizonBookmark (Mark as unread), checked against Teams' Last read line on the Randy 1:1.

- Compact density done (measured on winpc in compact, compared side by side).

- Auto-follow is the service's: posting OST TEST 80 in OST Test Team ▸ General from Teams sent only the message POST, no follow request; the choices are the synced userPersonalSettings.teamsAndChannelsSettings.autoFollow* (saved by Settings ▸ Chats). OST posts the same way, so OST behaves as Teams.
- Left: suggested replies (needs Teams' smart-reply service research).

- 2026-11-13: Suggested replies: Cortana writes conversation property quickReplyAugmentation; OST reads it (api::smart_replies, Backend.load_smart_replies on open and 2.5/7.5/12.5 s after someone else's message) and shows Teams' chips per its code (rules 142420 q/ie/oe; Griffel CSS from griffel-*.css on winpc). OST Test 1 (the winpc Teams account) never gets suggestions, so the chips were built from code; OST Test 2 sees them in OST (OST TEST 134: Yes, I'll check / I will / Let me check). Headers ruled out (OST TEST 130-132).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings ▸ Chats choices now act as in Teams: compact density, chat landing (last read or newest), the service's auto-follow, and suggested replies.

Suggested replies (this round):
- src/api/smart_replies.rs reads Cortana's quickReplyAugmentation (newest set with a reply; test).
- Backend.load_smart_replies; Conversation asks on opening a chat and shortly after someone else's message, and shows Teams' chip row above the compose box only for the newest message (not yours, not deleted), when the setting is on; a chip sends its text.
- Chip styles from Teams' Griffel CSS; spec §17 "Suggested replies".

Tests: cargo test --lib; live in OST as OST Test 2 (OST TEST 134).

Known: the winpc Teams account gets no suggestions, so the chips were built from Teams' code, not measured; Share file / meeting / workflow suggestions and the feedback button aren't built.
<!-- SECTION:FINAL_SUMMARY:END -->
