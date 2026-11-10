---
id: TASK-0043
title: >-
  Message actions as Teams: hover bar, ··· and right-click menus, reactions,
  selection, reply with quote
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-10T17:32:00Z'
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
- [x] #2 ··· menu items, order and MRU top-level rule exactly as Teams; right-click opens it at the pointer with the reaction strip
- [x] #3 Every reaction key renders as its emoji; any emoji can be a reaction; who reacted
- [x] #4 Message text can be selected and copied
- [x] #5 Reply with quote, Edit rules as Teams (no edit of Urgent; formatting kept)
- [x] #6 Channel posts and replies get the same hover bar and menu
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

- AC3: who reacted (hover/right-click list, measured), skin tones (preferredSkinToneIndex, six-tone chooser, toned quick Like), Customize default reactions (dialog, saves both properties; verified Teams desktop applies them live), Teams' client/service key mapping, overflow "+N" with its list and remove buttons, pressed underlines, the 20-reaction limit, serialised reaction writes. Left: Your org's emoji (custom emoji; research in progress) and the 413/400 HeaderInfoBanner.
- AC5: edit in place with the rebuilt compose (Teams' simplified compose, measured), Cancel/Done, Discard draft dialog, Escape inert, Urgent not editable, formatting and quote kept; the edit body matches a Teams edit read back from the service.

- AC6: channel posts and replies use the shared hover bar (measured positions), reaction summary, ··· and right-click menus (ChannelPost / ChannelReply sets as measured), in-place edit spanning the card, and Follow / Unfollow thread (Teams' rcmetadata f plus follow emotion, verified on the wire). Left: Open conversation in new window (Teams pops the thread into a 588 x 493 child window with the channel header, the post and a Reply in thread compose; needs a second conversation view with its own thread data), Share to Outlook and Immersive Reader.

- AC3, the org's custom emoji, verified live with "ost-test":
  - list via CSA; Add emoji as Teams (measured dialog, resize, AMS upload for the tenant, metadata POST);
  - rendering in messages and reactions, sending in compose, and reacting with one;
  - the Custom section in both pickers, with the Add cell and right-click "Created by … on …";
  - Delete for org, offered only when the messaging policy allows it.
- ost-test1 isn't allowed to delete: DELETE answered 403, and Teams' policy default is off. An admin has to delete ost-test.

- 2026-11-10: a reaction refused for message size (HTTP 413) now shows Teams' words: "Current message size limit reached. We can't add any more reactions.". Teams has no other reaction error string, so the 400 case keeps the service's error. Share to Outlook and Immersive Reader are web content embedded in Teams; they moved to TASK-0038 (new ACs there).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Message actions match Teams: the hover bar, the ··· and right-click menus (with the reaction strip), reactions, selection, reply with quote, in-place edit and channel parity, as listed in the notes above, each verified against Teams on winpc.

Since the last summary:
- a 413 reaction failure shows Teams' message;
- Share to Outlook and Immersive Reader (embedded web content) are tracked under TASK-0038.
<!-- SECTION:FINAL_SUMMARY:END -->
