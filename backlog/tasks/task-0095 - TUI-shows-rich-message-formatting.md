---
id: TASK-0095
title: TUI shows rich message formatting
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:58:00Z'
updated_date: '2026-11-10T16:13:00Z'
labels:
  - bug
  - tui
  - ux
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010). In OST group test, OST TEST 69 and 70 render as plain lines (group/00.txt). Headings, quotes, inline code, code blocks, bold and highlights look like ordinary text: "a quote", "inline code", "Heading two" and "let x = 1;" are indistinguishable from body text. Pictures show only as the word "Image" (group/12.txt).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Headings, quotes, inline code, code blocks, bold, italic, underline and strikethrough are visually distinct (terminal styles or markers)
- [x] #2 Pictures and files show as a labelled placeholder with their name or link
- [x] #3 Plain text messages look as they do today
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TUI shows Teams formatting.

What changed:
- New `tui::rich` turns a message's sanitized HTML and flow parts (the desktop's reading) into styled lines:
  - headings: bold, h1 also underlined;
  - quotes: a grey "│ " bar;
  - code blocks: a "▏ " bar, light cyan, indentation kept;
  - list items: • or 1.;
  - inline styles: bold, italic, underline, strikethrough, and inline code in light yellow;
  - pictures: "[Image]"; files: "[file] name" (magenta italic); emoticons keep their emoji.
- `MessageInfo` carries html/flow/files. Events, calls and recordings stay text-only.
- The messages pane wraps styled spans at spaces (code wraps anywhere) and keeps bars and bullet indents on wrapped rows. Plain messages read as before.

Tests:
- New `teams_formatting_becomes_line_kinds_and_styles`, `code_blocks_pictures_and_files_from_the_flow`, `formatting_shows_in_the_terminal` and `styled_text_wraps_at_spaces`.
- Live in tmux: OST group test's OST TEST 69/70 and OST threads test's OST TEST 87 code block. Styles were checked with `capture-pane -e` (heading 1 = SGR 1;4, inline code = colour 11).
<!-- SECTION:FINAL_SUMMARY:END -->
