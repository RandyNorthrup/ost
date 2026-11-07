---
id: TASK-0043
title: >-
  Message actions as Teams: hover bar, ··· and right-click menus, reactions,
  selection, reply with quote
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T08:28:00Z'
labels:
  - desktop
  - messages
dependencies: []
references:
  - docs/spec/messages-and-composer.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Message action gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/messages-and-composer.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Hover bar with the user's quick reactions (4 by default), More reactions picker, contextual action and ··· on every message, as the spec
- [ ] #2 ··· menu items, order and MRU top-level rule exactly as Teams; right-click opens it at the pointer with the reaction strip
- [ ] #3 Every reaction key renders as its emoji; any emoji can be a reaction; who reacted
- [ ] #4 Message text can be selected and copied
- [ ] #5 Reply with quote, Edit rules as Teams (no edit of Urgent; formatting kept)
- [ ] #6 Channel posts and replies get the same hover bar and menu
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- AC1: hover bar rebuilt from live DOM measurements, with Teams' emoticon images (catalogue and images from Teams' CDN), roamed quick reactions, More reactions, the divider, Edit / Reply with quote, and ···.
- Reaction pills and the add button match Teams; own messages' reactions sit at the bubble end.
- Teams' reaction picker: search, Recent (roamed recentReactions, written back as Teams does), categories and tab icons.
- Reply with quote: Teams' wire format, byte for byte (verified by reading back a Teams-sent and an OST-sent quote); the quote card in bubbles and in compose, measured; Teams web renders OST's quotes.
- Still to do: the ··· menu items, right-click with the reaction strip, who reacted, skin tones, Customize default reactions, Your org's emoji, text selection, in-place edit, and channel parity.
<!-- SECTION:NOTES:END -->
