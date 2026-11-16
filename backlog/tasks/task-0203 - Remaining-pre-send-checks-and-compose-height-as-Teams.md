---
id: TASK-0203
title: Remaining pre-send checks and compose height as Teams
status: To Do
assignee: []
created_date: '2026-11-16T14:25:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0085 built Teams' pre-send checks that apply to an existing chat or post (spec docs/spec/messages-and-composer.md §18). Not built: the new-chat checks (recipients, group size, roster limit), pasted-picture upload checks, Loop and Nearby checks, and roaming of reply drafts in channel threads. OST's compose box also has no maximum height, so a very long message pushes the "too large" banner out of view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New-chat, pasted-picture, Loop and Nearby checks block with Teams' wording as Teams does
- [ ] #2 Compose stops growing at Teams' maximum height and scrolls, so banners stay in view
- [ ] #3 Reply drafts in channel threads roam as Teams' do when Teams' roaming setting is on
<!-- AC:END -->
