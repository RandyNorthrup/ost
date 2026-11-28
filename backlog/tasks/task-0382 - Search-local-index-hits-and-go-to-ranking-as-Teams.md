---
id: TASK-0382
title: 'Search: local-index hits and go-to ranking as Teams'
status: To Do
assignee: []
created_date: '2026-11-28T05:37:00Z'
labels:
  - desktop
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0371 (PR #79). Teams adds hits from its own local index that the suggestions service doesn't return, so OST shows nothing where Teams shows a few: has:@Mentions with words typed, and is:Messages with an in:<channel> filter. In go-to mode, named group chats lack Teams' member line, and the order is by recent activity rather than Teams' relevance ranking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 has:@Mentions with words and is:Messages with in:<channel> list the same hits as Teams desktop for the same account (from OST's own cached messages where Teams uses its local index)
- [ ] #2 Go-to mode shows named group chats with Teams' member line and orders results as Teams does
<!-- AC:END -->
