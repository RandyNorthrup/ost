---
id: TASK-0043
title: >-
  Message actions as Teams: hover bar, ··· and right-click menus, reactions,
  selection, reply with quote
status: To Do
assignee: []
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T10:43:00Z'
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
- [x] #4 Message text can be selected and copied
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

- AC4: message text is selectable (a read-only TextEdit, kept to Teams' 20 px lines; the bubble now matches Teams' 35.3 px one-line height). Right-click with a selection gives Copy and Select all.
- AC2 (in progress): the ··· and right-click menus are built to the live measurements: the reaction strip on right-click, Teams' order, icons and shortcut letters, and More actions disabled while it is empty. Working now: Reply with quote, Edit, Copy link (Teams' link and clipboard HTML), Save and Unsave (rcmetadata), Delete, Pin and Unpin (thread pinnedItems), Read by N of M (horizons, with a submenu that opens a 1:1), and Mark as unread (Teams' bookmark; the chat list honours it). Each was verified live against the service. Still to do: Forward, Share to Outlook, Translation, Report, Immersive Reader, and the pinned banner.

- Forward: Teams' dialog rebuilt from live measurements. It searches people (directory), group chats and channels, picks recipients as pills, shows the forward-card preview and an optional note. The POST uses the source conversation with the target in the body, as the service expects.
- A one-person forward creates the 1:1 first when it doesn't exist (Teams' createThread with a unique roster). Several people reuse a group chat with exactly those members, else a new one.
- Teams' toast (measured: 288 x 46, bottom-left). Forwarded messages render as Teams' forward card; originalSentTime comes as ISO.
- Verified live: forwarded to the Randy 1:1 (the service replied 200 with the new id), and the toast and the card match winpc.
- Note: one early test attempt targeted a different directory "Randy Northrup" (Randy@techit.pw). Nothing was delivered: that thread didn't exist, and creating it wasn't implemented yet. The harness now picks by id.

- Pinned banner, saved bookmark, Translation and Report added. Report this message: the dialog matches this tenant's security-only variant (measured); the submit is Teams' unified report API (POST {mt}/beta/reports), unit-tested.
- A live report was NOT submitted: it reaches the tenant admins and Microsoft, so that needs the user's explicit OK.
<!-- SECTION:NOTES:END -->
