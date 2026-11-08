---
id: TASK-0058
title: Others' own mute state on meeting tiles and the roster (endpointState)
status: To Do
assignee: []
created_date: '2026-11-08T11:13:00Z'
labels:
  - calls
  - meetings
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams shows mic-off on a participant who muted themselves: a participant is muted when its audio stream is serverMuted or an endpoint's endpointState.state.isMuted is true (calling-pluginless). OST's roster carries no endpointState, so OST only shows server mutes. Find how Teams' clients get endpointState in roster updates (likely a clientEndpointCapabilities bit or roster subscription field), then use it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Find (and record in docs/spec) how roster updates come to carry endpointState for each endpoint
- [ ] #2 A participant who mutes themselves shows mic-off on their tile and in the People pane, as on winpc
- [ ] #3 Unmuting clears it
<!-- AC:END -->
