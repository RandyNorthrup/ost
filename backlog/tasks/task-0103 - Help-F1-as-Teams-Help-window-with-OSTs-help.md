---
id: TASK-0103
title: Help (F1) as Teams' Help window, with OST's help
status: To Do
assignee: []
created_date: '2026-11-11T01:52:00Z'
labels:
  - help
dependencies: []
documentation:
  - docs/spec/feedback-and-help.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Help window (help.svc.cloud.microsoft) becomes OST's native Help window over bundled Markdown articles in docs/help (spec docs/spec/feedback-and-help.md §4).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 F1, Settings and more > Help, and the Help app open a Help window laid out as Teams' (title row, header with More Help actions: Reload app, About, Share app)
- [ ] #2 Help home: Search help, Help for OST, three hero cards, Browse all help (Teams' nine categories), Featured topics, Licence | Privacy footer
- [ ] #3 Search finds OST articles; categories list their articles; articles render natively with Was this information helpful? Yes/No (to the feedback forms) and Edit on GitHub
- [ ] #4 docs/help holds articles for every category, bundled so Help works offline
<!-- AC:END -->
