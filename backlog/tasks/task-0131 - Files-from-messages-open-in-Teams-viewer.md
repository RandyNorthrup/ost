---
id: TASK-0131
title: Files from messages open in Teams' viewer
status: To Do
assignee: []
created_date: '2026-11-13T23:54:00Z'
labels:
  - desktop
  - messages
  - files
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Clicking a file card in a message (its head or preview) makes Teams open the file full-pane in its own viewer (measured on winpc 2026-11-13 with ost-share-test.txt): a header with the type icon and name, Close and ···, and the file under it (OneDrive's viewer: a text page with line numbers). OST still hands the file to the browser (or the desktop app per Settings).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking a message's file opens it in OST's viewer with Teams' header (icon, name, Close, ···)
- [ ] #2 Text, pictures, PDF and Office files show as Teams shows them, and Close returns to the conversation
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->
