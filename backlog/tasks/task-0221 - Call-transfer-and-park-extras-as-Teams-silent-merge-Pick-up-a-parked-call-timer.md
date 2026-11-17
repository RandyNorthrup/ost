---
id: TASK-0221
title: >-
  Call transfer and park extras as Teams: silent merge, Pick up a parked call,
  timer
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-17T17:56:00Z'
updated_date: '2026-11-17T19:19:00Z'
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
- [x] #2 The Calls view has Teams' 'Pick up a parked call' entry and dialog; entering a pickup code retrieves the call
- [ ] #3 OST as the person moved by a consult transfer that Teams starts carries on in the new call, verified live
- [ ] #4 The call timer keeps the call's original start when a call is replaced by a transfer, park pickup or merge, as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-17 (merged 1da0d70):
  - Silent merge: OST keeps each person's replacement link from roster events and names the held person's leg in replacementDetails, so the service moves them in; it falls back to an invite. Unit-tested, not yet live.
  - "Pick up a parked call" dialog, from Teams' unpark bundle, opened from the Calls view's More menu. Main-thread check of the capture: OK.
  - The call clock carries over when a call is replaced.
- Left: a live three-person silent merge, a Teams-started consult transfer moving OST, and a live timer check. All need winpc.
<!-- SECTION:NOTES:END -->
