---
id: TASK-0095
title: TUI shows rich message formatting
status: To Do
assignee: []
created_date: '2026-11-10T15:58:00Z'
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
- [ ] #1 Headings, quotes, inline code, code blocks, bold, italic, underline and strikethrough are visually distinct (terminal styles or markers)
- [ ] #2 Pictures and files show as a labelled placeholder with their name or link
- [ ] #3 Plain text messages look as they do today
<!-- AC:END -->
