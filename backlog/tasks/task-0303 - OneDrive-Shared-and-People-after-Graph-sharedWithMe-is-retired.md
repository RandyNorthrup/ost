---
id: TASK-0303
title: OneDrive Shared and People after Graph sharedWithMe is retired
status: To Do
assignee: []
created_date: '2026-11-25T15:49:00Z'
labels:
  - onedrive
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Microsoft's Graph /me/drive/sharedWithMe is deprecated like drive/recent: it degrades until November 2026 and then stops returning data. OST's OneDrive Shared view and Browse by People (src/api/drive.rs shared_with_me, by_people) still call it. Teams' OneDrive app reads shared files from OneDrive's own services; capture which on winpc and move OST to it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST's OneDrive Shared view and Browse files by People keep working without /me/drive/sharedWithMe, with the same items and order Teams shows
<!-- AC:END -->
