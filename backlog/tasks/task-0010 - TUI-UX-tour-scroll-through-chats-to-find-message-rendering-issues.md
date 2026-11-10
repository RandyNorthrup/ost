---
id: TASK-0010
title: 'TUI UX tour: scroll through chats to find message rendering issues'
status: Done
assignee:
  - '@claude'
created_date: 2026-02-05 23:23
updated_date: '2026-11-10T16:00:00Z'
labels:
  - tui
  - ux
  - qa
dependencies: []
references:
  - docs/specs/tui.txt
  - .claude/skills/tui-ux-tour/SKILL.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run a targeted TUI UX walking tour focused on message rendering quality. Open several chats and channels, scroll through message history, and look for rendering problems with rich content: markdown formatting (bold, italic, headers, lists), inline code, code blocks, tables, links, mentions, emojis, long URLs, and multi-line messages. Create a new backlog task for each rendering issue found.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At least 5 different chats/channels scrolled through using the tui-ux-tour skill
- [x] #2 Each rendering issue found is filed as a separate backlog task with screenshot evidence
- [x] #3 Rich content types checked: markdown, inline code, code blocks, tables, links, mentions, emojis
- [x] #4 Tour summary documents which content types render correctly and which do not
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TUI UX tour, 2026-11-10, run with the tui-ux-tour steps in tmux at 120×40 on linuxlt. A script opened each conversation and scrolled its history up in 12 steps, capturing the screen at every step.

Toured (7): OST Test Team ▸ OST threads test, OST test channel, OST test channel 2, General; chats OST Test 1 (You), OST group test, OST calendar test. Randy Northrup's real chat was left out.

Renders correctly:
- plain and multi-line text, wrapped to the pane;
- emoji (😮);
- code block lines with their indentation;
- channel, team and tag mentions;
- link text;
- card text ("Take a look at this app. / Help");
- meeting recordings (since TASK-0011);
- sender and time headers and own-message markers;
- the help overlay, the toolbar and the chat list (since TASK-0012/0013/0092).

Renders wrongly (one task each):
- TASK-0093: the TUI read history without Teams' parameters or older pages. (The "No messages yet" seen in OST test channel and OST test channel 2 was correct: those channels hold only 4 thread events.)
- TASK-0094: the scroll arrows overwrite the last character of edge timestamps.
- TASK-0095: rich formatting (headings, quotes, inline code, code blocks, bold, highlights) looks like plain text; pictures show as "Image".
- TASK-0096: one @mention lost its name ("mention for check").
- TASK-0097: post subjects aren't shown.

Not seen in the tour's data: tables and long URLs (no test messages contain them).
<!-- SECTION:FINAL_SUMMARY:END -->
