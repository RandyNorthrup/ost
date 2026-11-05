---
id: TASK-0022
title: Profile photos for people and teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T16:07:00Z'
updated_date: '2026-11-05T16:43:00Z'
labels:
  - desktop
  - ui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams desktop shows each person's profile photo (chat list, conversation, header) and each team's picture; OST draws initials everywhere. Reference: Windows Teams on winpc (ost-test1).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 People with a profile photo show it in the chat list, the conversation and the chat header, falling back to initials only when they have none
- [x] #2 Teams and channels show the team's picture as Teams does
- [x] #3 Photos are cached on disk owner-only and refreshed, not refetched on every view
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Avatars show Teams pictures (photos, or Teams-generated initials images) from the middle-tier profilepicturev2 service, cached owner-only for a day.

- Backend photo_for(id, name) + photo_ready signal; id validation unit-tested.
- Canvas-clipped circle/rounded-square drawing, renderer independent.
- Used in chat list, conversation, header, title bar, teams, calls, people picker, call toast and stage.

Tests: cargo test (photo_targets_accept_only_object_ids); side-by-side with Teams desktop on winpc.
<!-- SECTION:FINAL_SUMMARY:END -->
