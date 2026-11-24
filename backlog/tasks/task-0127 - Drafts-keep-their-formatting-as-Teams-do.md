---
id: TASK-0127
title: Drafts keep their formatting as Teams' do
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T05:13:00Z'
updated_date: '2026-11-16T07:44:00Z'
labels:
  - chat
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST saves a chat's unsent draft as plain text (backend.setDraft with root.plainText()), so bold, lists, quotes, code blocks and tables flatten when you switch chats or restart (seen 2026-11-12: a table draft came back as lines). Check what Teams' local drafts keep and match it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A formatted draft (incl. a table) comes back as Teams' does after switching chats and after a restart
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Drafts keep their formatting as Teams' do, after switching chats and after a restart. That covers headings, bold, italic, underline, strike, inline code, highlight, quotes, code blocks with their language, lists, links, mentions, emoji/GIF/sticker pictures and tables.

Changes:
- A draft is saved as its text, the compose box's HTML export (the same one sending uses) and its pictures. Drafts saved by older versions still load, as plain text.
- RichText.importHtml rebuilds the HTML with the formatting bar's own marks. src/api/compose_blocks.rs parses it, and richtext.cpp rebuilds it.
- Fixed: when switching chats, the call window's chat pane saved its empty compose box over the real draft. A compose box now saves only if it changed since loading.
- The Drafts list preview stays plain text.
- Harness: --draft-format-test, with --draft-format-restart.

Tests:
- 9 compose_blocks tests and 4 draft tests pass.
- On the merged build: "same after switching true", "same after restart true", "cleared true".
- Nothing was sent.

Follow-up: editing a sent message still loads through Qt's HTML reader; importHtml could serve it too.
<!-- SECTION:FINAL_SUMMARY:END -->
