---
id: TASK-0174
title: Inline code box in received messages as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T07:37:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams draws a thin box around inline code. Qt's rich text can't draw it directly; an overlay behind the text (as compose already does for quotes and code) can.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inline code in received messages has Teams' box, measured on winpc
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Received messages draw inline code in Teams' box: a rounded, bordered box around the code, measured on winpc. It works in light, dark and High contrast, and inside quotes and text between pictures.

Changes:
- CodeBoxes.qml draws the boxes behind the message text.
- The C++ helper reserves the box's side space as letter spacing and reports where each code run lands on each line. rich_text.rs turns that into one box per line, as Chromium does, with borders rounded to whole device pixels and never thinner than one.
- Colours: white with #D1D1D1 (light), #292929 with #666666 (dark), black with white (High contrast).
- --chat-shot gained --jump=<text> to show an older message.
- Spec: docs/spec/messages-and-composer.md has the measurements.

Tests:
- 5 new unit tests pass.
- Before and after shots of OST TEST 70 in all three themes; the merged build was checked on linuxlt.

Not seen live: code that wraps across lines (covered by unit tests only).
<!-- SECTION:FINAL_SUMMARY:END -->
