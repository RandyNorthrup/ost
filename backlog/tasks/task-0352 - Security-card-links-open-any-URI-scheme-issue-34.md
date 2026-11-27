---
id: TASK-0352
title: 'Security: card links open any URI scheme (issue #34)'
status: To Do
assignee: []
created_date: '2026-11-27T15:36:00Z'
labels:
  - security
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #34 (Serph91P): links from card content (Adaptive Card Action.OpenUrl and markdown links, RichTextBlock selectAction, Hero card buttons, Connector card links) reach Qt.openUrlExternally with no scheme check, so file:, smb:, sftp:, davs: and other apps' custom schemes go to xdg-open without confirmation; RichTextBlock selectAction.url is concatenated into HTML unescaped. Message HTML already goes through safe_url().
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every remote-data call site of Qt.openUrlExternally goes through one native gate that allows only https, http, mailto, tel and OST's own schemes and refuses everything else, matching what Teams desktop opens from cards
- [ ] #2 Card markdown links and RichTextBlock selectAction URLs are scheme-checked and HTML-escaped, so a card can't inject markup
- [ ] #3 Unit tests cover the gate and the escaping; issue #34 is answered and closed after the fix is merged
<!-- AC:END -->
