---
id: TASK-0066
title: Avatar initials colours as Teams picks them
status: To Do
assignee: []
created_date: '2026-11-09T03:20:00Z'
labels:
  - desktop
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST colours initials avatars with its own name hash. Teams (Fluent colorful avatar) picks the colour differently: for example, in the Transcript pane and the gallery, OST Guest 1 is yellow in Teams and blue in OST. People whose photo OST fetches from Teams' photo service already get Teams' colour; guests and anyone drawn locally don't.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Locally drawn initials avatars use the same colour as Teams for the same person (checked against winpc for an org user, a guest and a group)
- [ ] #2 The colour rule is documented in docs/spec with its source in Teams' code
<!-- AC:END -->
