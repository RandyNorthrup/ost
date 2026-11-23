---
id: TASK-0264
title: Calendar fixes from the calendar polish pass
status: In Progress
assignee: []
created_date: '2026-11-23T21:21:00Z'
updated_date: '2026-11-23T21:21:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0262: Teams' high contrast calendar draws yellow event tiles where OST draws black; OST's calendar toolbar shows "Filter applied" for ost-test1 where Teams shows no filter; Send update on a non-meeting event fails with "Conversation id cannot be null".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 High contrast calendar event tiles match Teams' colours in every view
- [ ] #2 The calendar toolbar shows Filter applied only when Teams does, with the same filter state
- [ ] #3 Send update on a non-meeting event sends the update to its attendees as Teams does
<!-- AC:END -->
