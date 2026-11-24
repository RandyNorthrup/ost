---
id: TASK-0278
title: Video tile menu, room captions and room remote strings as Teams
status: In Progress
assignee: []
created_date: '2026-11-24T15:00:00Z'
updated_date: '2026-11-24T15:00:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0273: Teams has a ··· menu on video tiles (one of the places it offers Control Room System), OST has none; an OST room invited into a meeting can't run captions, so its remote has no Captions; the room remote's strings come from Teams' extensibility app, which OST's runtime string table doesn't fetch, so they stay English.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Video tiles have Teams' ··· menu with Teams' items for each kind of participant, each working as in Teams
- [ ] #2 An OST room invited into a meeting runs captions as a Teams Room does, and its remote offers Captions
- [ ] #3 The room remote's strings are translated from Teams' extensibility app strings, fetched at runtime like the others
<!-- AC:END -->
