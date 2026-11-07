---
id: TASK-0044
title: 'Compose as Teams: @mention picker, quotes, formatting kept'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T19:45:00Z'
labels:
  - desktop
  - messages
dependencies: []
references:
  - docs/spec/messages-and-composer.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Compose gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/messages-and-composer.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 @ opens Teams' mention picker (people, tags, everyone/channel/team per rules) and sends real mentions
- [x] #2 Quoted replies compose and send as Teams' quote
- [x] #3 Enter / Ctrl+Enter / Shift+Enter behave as Teams' setting rules
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Compose rebuilt as ComposeBox.qml to Teams' measured simplified compose (single-line and multiline states, side and bottom toolbars, formatting bar with Discard, focus line, Shift+Enter hint linking to Settings).
- AC2: quoted replies compose (card with Remove Reference) and send as Teams' quote (verified earlier byte for byte).
- AC3: Enter rules as Teams (Ctrl+Enter sends; Enter sends only with the Default setting and the bar closed; Shift+Enter new line).
- Delivery options via "+" (measured flyout and listbox), IMPORTANT!/URGENT! header, Ctrl+Shift+I, Urgent rules; importance sent with the message.
- Left: AC1 @mention picker; the full formatting bar (highlight, colour, size, quote, link, code block, rich style, indent, rule, table, undo/redo, overflow); fun picker (GIFs, stickers); Attach menu (cloud files); Schedule message; Record video clip; Loop; installed apps in "+"; drafts sync; pre-send checks.

- AC1 (partial): @ opens Teams' picker (measured); person mentions insert as per-word tokens and send in Teams' wire format (verified rendered by Teams). Left: Everyone / tags / channel / team mentions, Add someone to the chat, Share contact, member emails in rows, mentions kept when editing.

- Teams' unified fun picker replaces the old emoji popup, all measured on winpc:
  - All, Emoji, GIFs and Stickers tabs, search, See all, the GIPHY credit and View Terms;
  - GIF categories and results come from the middle tier's giphy command, trending when there is no query;
  - Teams' sticker catalogue ships with OST (674 stickers), including Recent and the packs;
  - the inline caption editor draws the sticker and uploads it to AMS.
- Picks go into the compose box and are sent byte for byte as Teams sends them (emoticon span, GIF, sticker, AMS sticker). Verified on winpc, where Teams rendered OST's message.
- Received GIFs and stickers render (earlier commit). Emoticon-only messages no longer vanish.
- Left: the Custom (org emoji) section with Teams' Add emoji dialog; Teams' jumbo emoji-only messages; Fluent emoticon pictures inside message text; GIF and sticker order in mixed messages; GIFs and stickers in replies and edits.
<!-- SECTION:NOTES:END -->
