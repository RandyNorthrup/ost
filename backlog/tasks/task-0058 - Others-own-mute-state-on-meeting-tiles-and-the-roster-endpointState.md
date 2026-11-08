---
id: TASK-0058
title: Others' own mute state on meeting tiles and the roster (endpointState)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-08T11:13:00Z'
updated_date: '2026-11-08T15:35:00Z'
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
- [ ] #4 Muting or unmuting OST shows on its tile in Teams (OST posts updateEndpointState as Teams does)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. roster.rs: a muted field per Teams' rule (unmuted only if an endpoint's first audio stream isn't serverMuted and its endpointState.state.isMuted isn't true); keep it through deltas without endpoints; unit tests from the captured roster.
2. QML: tiles, People pane and Mute all availability use muted.
3. outgoing.rs: keep the conversation's updateEndpointState link; on mute/unmute post {from, endpointState:{state:{isMuted}, endpointStateSequenceNumber}}; the join's endpointState carries the starting mute.
4. Verify live: Guest 1 mutes/unmutes (OST tile and People); OST mutes/unmutes (Teams web guest shows it); record in docs/spec.
<!-- SECTION:PLAN:END -->
