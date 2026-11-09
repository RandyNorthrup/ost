---
id: TASK-0044
title: 'Compose as Teams: @mention picker, quotes, formatting kept'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-09T13:12:00Z'
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

- Custom (org emoji) section with Teams' Add emoji dialog: done (add, send, react verified live on Teams web).
- Big emoticons (1-3 emoticons/custom emoji alone at 50 px, no bubble) and Teams' Fluent emoticon pictures inside text: done (63a0563).

- Pictures keep their place: text, GIFs, stickers and pictures show in the order written, with Teams' blank lines (measured on Teams web).
- Edits keep emoticons, custom emoji, GIFs, stickers and pictures (edit_html/edit_media), verified live with two edits (4950794).
- Left: GIFs/stickers in quoted replies (quote preview).

- Quoted replies: preview text as Teams' QuotedReplyContent (📷 for pictures, 🎥 video, emoticon chars, :custom:, list numbering); verified live, Teams web rendered OST's reply.

- Channel picker: team and channel mention rows (measured), Teams' wire format verified byte for byte live; members-only suggestions in channels; matched text bold; "Suggestions" header always.
- Channel post highlights (bar + badge, Teams' priority order), measured on winpc (799e0a1).
- Fixed: Everyone mentions were sent as plain text.
- Left in AC1: Share someone's contact info, Add agent, Add someone to the chat, tags, mentions kept when editing.

- Share someone's contact info: dialog measured on winpc, wire byte for byte, render as Teams (899c8f5).
- Mentions kept when editing (tokens back in the edit box; edits send their own mentions list); verified live on OST TEST 65.
- Left in AC1: Add agent, Add someone to the chat (needs the Add people dialog), tags.

- Add someone to the chat (group chats) opens Teams' Add dialog; roster flyout rebuilt to Teams' measurements with Add people (451af76). Adding a member is unit-tested only; a live add needs a person the user approves.
- Left in AC1: Add agent (bots), tags.

- Add people verified live: randy@techit.pw (user's own account, approved) added to OST group test and removed again from OST; Teams web showed both control messages. Remove button + Teams' confirm dialog added.
- Left: Leave (shown with >2 people), Add agents, presence for every member in the flyout.

- Formatting bar (6ca36fe): all Teams groups except tables, Teams' overflow (flex gap calc(100% - 49rem)), popups measured (highlight/font colour palettes, font size, rich style, insert link), code block with Teams' languages, RichText C++ layer exporting clean HTML -> Teams wire; OST TEST 69 rendered by Teams web like its own.
- Received formatting: quotes, code cards, colours/sizes, headings (measured 18/300, 14/700, 12/700), inline code.
- Left: tables (insert/rows/columns/delete), code card ··· menu, syntax colours, inline-code hairline box (Qt rich text limit), Rich style button width in bar never shows (always overflows at 458).

- Tags (AC1): the @ picker offers the team's tags after the team and channel (CSA tagCards; lavender circle with the Tag icon, "1 person"/"N people"), sends Teams' tag mention (readonly wrapper, mentionType "tag", mri = tagId), and keeps it when editing. A tag you are in counts as mentioning you (orange bold, @ badge), as Teams' currentUserTagIds. Activity names tag mentions "{name} mentioned {tag}" under the Tag mentions filter. Verified live: OST's "OST TEST 70" renders on winpc Teams exactly like Teams' own "OST TEST 69".
- Left in AC1: Add agent to the chat/channel (agent picker), and the Everyone limits banner.
<!-- SECTION:NOTES:END -->
