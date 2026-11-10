---
id: TASK-0013
title: 'Audit compose toolbar: remove or implement non-functional controls'
status: Done
assignee:
  - '@claude'
created_date: 2026-02-06 00:09
updated_date: '2026-11-10T15:39:00Z'
labels:
  - bug
  - tui
  - ux
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The compose toolbar displays formatting and action icons (bold, italic, underline, strikethrough, link, attach, emoji, camera, mic, send) but it is unclear which of these are functional. Likely none of them are wired up -- displaying non-functional controls misleads the user into thinking the TUI supports rich text formatting, file attachments, voice recording, etc.

Audit each toolbar item:
1. Test which controls actually work by sending messages to 48:notes
2. Remove controls that have no backend implementation
3. Keep only controls that are functional (likely just the send arrow, if even that)
4. If plain text is all that's supported, simplify the toolbar to reflect that

The toolbar should only show controls that actually do something when activated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every icon in the compose toolbar has a working action when activated, or is removed
- [x] #2 Sending a plain text message to 48:notes via the compose box works end-to-end
- [x] #3 No non-functional controls are displayed in the toolbar
- [x] #4 The send button (or Enter key) successfully sends and the message appears in the channel
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TUI compose toolbar now shows only what works.

Before, it drew bold, italic, underline, strikethrough, link, attach, emoji, camera and microphone icons. None of them was wired up (the TUI has no mouse handling and sends plain text).

Changes:
- `compose::render_toolbar` draws only a "Ctrl+Enter: new line" hint and the send arrow labelled with its key ("Enter ➤"). On a narrow box only the arrow stays.

Tests:
- New `the_toolbar_shows_only_working_controls` (none of the old icons are drawn; the arrow survives a 12-column box).
- Live on linuxlt (tmux, 160×45): in the notes-to-self chat (48:notes), typing "OST TEST 95 from the TUI" and pressing Enter showed "Message sent", and the message appeared in the list.

Follow-ups found while testing (new tasks): the help overlay lists shortcuts the TUI doesn't handle, and the chat list shows system streams (48:drafts, 48:threads, …) and raw ids as chats.
<!-- SECTION:FINAL_SUMMARY:END -->
