---
id: TASK-0127
title: Drafts keep their formatting as Teams' do
status: To Do
assignee: []
created_date: '2026-11-13T05:13:00Z'
labels:
  - chat
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST saves a chat's unsent draft as plain text (backend.setDraft with root.plainText()), so bold, lists, quotes, code blocks and tables flatten when you switch chats or restart (seen 2026-11-12: a table draft came back as lines). Check what Teams' local drafts keep and match it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A formatted draft (incl. a table) comes back as Teams' does after switching chats and after a restart
<!-- AC:END -->
