---
id: TASK-0131
title: Files from messages open in Teams' viewer
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T23:54:00Z'
updated_date: '2026-11-14T00:38:00Z'
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
- [x] #1 Clicking a message's file opens it in OST's viewer with Teams' header (icon, name, Close, ···)
- [x] #2 Text, pictures, PDF and Office files show as Teams shows them, and Close returns to the conversation
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams' viewer (entity header, Close, ···) and its SharePoint embed.aspx text view on winpc (CDP read-only)
2. Move FilePreview's body to PreviewBody.qml with an embedded (light) style
3. FileViewer.qml in Main over the chat area; the card opens it; ··· reuses the card menu
4. Harness --fileviewer-test; recheck --preview-test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams embeds OneDrive's embed.aspx (Monaco for text). OST draws the same layout natively; no minimap. Office files show as PDF pages (Graph conversion), as OST's Preview does; Teams shows Office for the web
- 16.38 px name drawn at 16 (Qt pixelSize is whole pixels); Cascadia Mono stands in for Consolas
- Harness --fileviewer-test (txt from OST TEST 121 + ost-open-test.docx), --preview-test still passes
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Clicking a file in a message now opens Teams' viewer instead of the browser.

Changes:
- FileViewer.qml: over the chat list and conversation (right of the app bar): Teams' 61 px header (type icon, bold name, Close, ··· with the card's menu) and the file in OneDrive's embedded style.
- PreviewBody.qml: the preview body moved out of FilePreview (text, picture, PDF/Office as PDF, no preview), with an `embedded` style matching embed.aspx's text view.
- Conversation emits openFileRequested; Main closes the viewer on app or chat change; the card menu can sit a gap under its button.
- ft-genericfile-20 / ft-video-20 icons; spec §17.

Tests: harness --fileviewer-test and --preview-test on linuxlt; compared with Teams on winpc.

Known: Office files are PDF pages, not Office for the web; Monaco's minimap isn't drawn.
<!-- SECTION:FINAL_SUMMARY:END -->
