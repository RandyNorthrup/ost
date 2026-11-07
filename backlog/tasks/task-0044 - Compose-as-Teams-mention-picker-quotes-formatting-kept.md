---
id: TASK-0044
title: 'Compose as Teams: @mention picker, quotes, formatting kept'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T14:48:00Z'
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
<!-- SECTION:NOTES:END -->
