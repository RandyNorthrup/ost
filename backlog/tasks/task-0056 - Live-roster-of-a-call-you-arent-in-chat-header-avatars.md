---
id: TASK-0056
title: Live roster of a call you aren't in (chat header avatars)
status: To Do
assignee: []
created_date: '2026-11-08T04:07:00Z'
labels:
  - calls
  - chat
dependencies: []
references:
  - desktop/qml/Conversation.qml
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' chat header shows who is in a live meeting or group call (participants-live-roster-list: 32 px avatars overlapping by 10, up to 5 then +N) even when you haven't joined. OST only knows who started the call (the thread's liveness entry), so the meeting chat's live band and the group-call pill show no or one avatar. Needs research into how Teams gets that roster for an unjoined call.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A live meeting's chat header shows the avatars of the people in the meeting, as Teams does, without joining
- [ ] #2 A group chat's call pill shows everyone in the call, not just who started it
<!-- AC:END -->
