---
id: TASK-0174
title: Inline code box in received messages as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T05:21:00Z'
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
- [ ] #1 Inline code in received messages has Teams' box, measured on winpc
<!-- AC:END -->
