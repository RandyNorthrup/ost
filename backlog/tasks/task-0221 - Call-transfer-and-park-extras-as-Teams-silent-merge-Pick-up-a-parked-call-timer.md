---
id: TASK-0221
title: >-
  Call transfer and park extras as Teams: silent merge, Pick up a parked call,
  timer
status: To Do
assignee: []
created_date: '2026-11-17T17:56:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gaps left after TASK-0186: OST's merge invites the held person (they ring) where Teams moves them in silently; the Calls view has no 'Pick up a parked call' dialog; OST as the person moved by a Teams-started consult transfer is untested; the call timer restarts when a call is replaced.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Merge Calls moves the held person into the group call without ringing them, as Teams
- [ ] #2 The Calls view has Teams' 'Pick up a parked call' entry and dialog; entering a pickup code retrieves the call
- [ ] #3 OST as the person moved by a consult transfer that Teams starts carries on in the new call, verified live
- [ ] #4 The call timer keeps the call's original start when a call is replaced by a transfer, park pickup or merge, as Teams
<!-- AC:END -->
