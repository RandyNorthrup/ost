---
id: TASK-0198
title: Other apps' tabs and channel page/list tabs as Teams
status: To Do
assignee: []
created_date: '2026-11-16T09:43:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Add a tab picker opens each app's own configuration page (OneNote, PDF, Excel, Whiteboard…) in a TeamsJS host, and a channel's "+" menu offers New page, Existing page, New list and Existing list. OST shows these but can't save them yet: it can't host Teams' embedded app pages (TASK-0053).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Choosing an app other than Website in the picker shows that app's configuration page and Save adds its tab for everyone, as in Teams
- [ ] #2 A channel's New page, Existing page, New list and Existing list add their tabs as in Teams
<!-- AC:END -->
