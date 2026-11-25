---
id: TASK-0320
title: 'OneDrive Shared view: By you tab, filter pills, People chips'
status: To Do
assignee: []
created_date: '2026-11-25T21:11:00Z'
updated_date: '2026-11-25T22:15:00Z'
labels:
  - onedrive
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0303 moved OneDrive's Shared ▸ With you and Browse files by People to OneDrive's own services with Teams' items and order. Teams' Shared view also has a By you tab (_api/web/onedriveshareditems?$top=1000), type filter pills and a place line under each name, and its People view shows each person's files as chips with a +N, where OST still lists a file count.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OneDrive Shared has With you and By you tabs listing what Teams lists, in Teams' order
- [ ] #2 Shared's filter pills and People's file chips (+N) look and behave as Teams' do
- [ ] #3 Shared's columns are Teams' (Name with its place line, Date shared, Shared by, Activity; no File size or Sharing)
<!-- AC:END -->
