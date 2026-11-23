---
id: TASK-0254
title: Chat fixes from the release screenshot pass
status: In Progress
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T15:54:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bugs seen while taking the 0.2.0 screenshots (OST Test 2/3 on linuxlt). Each must behave as Teams desktop does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An empty unnamed group chat shows Teams' generated name (its members) in the chat list, never the raw 19:…@thread.v2 id
- [ ] #2 A chat opened from Activity or the chat list after viewing a channel or post shows only the chat's own header tabs
- [ ] #3 Starting a brand-new 1:1 chat and sending the first message works as in Teams (no 404 CONVERSATION_DELETED), and a failed message is never left in another profile's outbox (outbox is per profile)
- [ ] #4 A new group chat shows in every member's chat list as Teams lists it, without the member opening it first
- [ ] #5 The Like reaction shows Teams' thumbs-up emoji everywhere reactions appear
<!-- AC:END -->
