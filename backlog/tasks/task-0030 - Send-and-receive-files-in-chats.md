---
id: TASK-0030
title: Send and receive files in chats
status: To Do
assignee: []
created_date: '2026-11-05T17:58:00Z'
labels:
  - desktop
  - chat
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams users share files in chats: the sender uploads to their OneDrive (Microsoft Teams Chat Files), shares with the chat, and the message carries a file record. OST showed nothing for file messages and could not send files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Messages with files show Teams-style file cards that open in the browser and download to the Downloads folder
- [ ] #2 Files picked with the attach button are uploaded, shared with the chat's members and sent (with optional text), appearing in Teams as normal file cards
- [ ] #3 Large files upload in chunks; files over 250 MB are refused with a message
<!-- AC:END -->
