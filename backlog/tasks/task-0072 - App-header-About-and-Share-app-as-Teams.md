---
id: TASK-0072
title: App header About and Share app as Teams
status: To Do
assignee: []
created_date: '2026-11-09T07:57:00Z'
labels:
  - desktop
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A personal app's header menu in Teams (Help window, measured on winpc 2026-11-09: More <app> actions) offers Reload app, About and Share app. About opens Teams' app details dialog (app-details-northstar-dialog, 898.7 x 563.67: the app's tile and name, developer, rating and review counts, installs in the last month, Works in, pricing, then its description and details). Share app opens Teams' Share form (Share to picker, 'Say something about this' with 'Take a look at this app.' and the app's card, Share). OST's app header offers Reload app only until these exist.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 About opens Teams' app details dialog for the app, with the same sections and data as Teams (measured on winpc)
- [ ] #2 Share app opens Teams' Share form; sharing posts the app card as Teams does (tested only into OST group test or OST Test Team)
- [ ] #3 Both appear in the app header menu in Teams' order (Reload app, divider, About, Share app)
<!-- AC:END -->
