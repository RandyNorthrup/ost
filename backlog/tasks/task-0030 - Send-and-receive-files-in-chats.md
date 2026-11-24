---
id: TASK-0030
title: Send and receive files in chats
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T17:58:00Z'
updated_date: '2026-11-05T17:58:00Z'
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
- [x] #1 Messages with files show Teams-style file cards that open in the browser and download to the Downloads folder
- [x] #2 Files picked with the attach button are uploaded, shared with the chat's members and sent (with optional text), appearing in Teams as normal file cards
- [x] #3 Large files upload in chunks; files over 250 MB are refused with a message
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
File cards with open/download; sending via OneDrive upload (simple or chunked session, 250 MB cap), Graph invite to members, Teams files record. Tested: OST->Teams web card, Teams desktop->OST card, download to ~/Downloads; unit tests for parsing and path encoding.
<!-- SECTION:FINAL_SUMMARY:END -->
