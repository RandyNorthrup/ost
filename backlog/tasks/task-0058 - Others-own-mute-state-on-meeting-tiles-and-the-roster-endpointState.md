---
id: TASK-0058
title: Others' own mute state on meeting tiles and the roster (endpointState)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T11:13:00Z'
updated_date: '2026-11-08T16:00:00Z'
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
- [x] #1 Find (and record in docs/spec) how roster updates come to carry endpointState for each endpoint
- [x] #2 A participant who mutes themselves shows mic-off on their tile and in the People pane, as on winpc
- [x] #3 Unmuting clears it
- [x] #4 Muting or unmuting OST shows on its tile in Teams (OST posts updateEndpointState as Teams does)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. roster.rs: a muted field per Teams' rule (unmuted only if an endpoint's first audio stream isn't serverMuted and its endpointState.state.isMuted isn't true); keep it through deltas without endpoints; unit tests from the captured roster.
2. QML: tiles, People pane and Mute all availability use muted.
3. outgoing.rs: keep the conversation's updateEndpointState link; on mute/unmute post {from, endpointState:{state:{isMuted}, endpointStateSequenceNumber}}; the join's endpointState carries the starting mute.
4. Verify live: Guest 1 mutes/unmutes (OST tile and People); OST mutes/unmutes (Teams web guest shows it); record in docs/spec.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Roster endpointState was there all along (the first check read an info-level log).
- Teams' muted rule implemented; OST posts updateEndpointState; server-muted unmute goes through the unmute link and waits for the roster, as Teams does.
- Live-verified both ways with Teams web guests (commit 80d9ccd).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting mute state now matches Teams in both directions.

Changes:
- roster.rs: `muted` per Teams' rule (an endpoint's first audio stream not serverMuted and its endpointState not muted means unmuted); kept through deltas; `own_server_muted` reads our endpoint.
- outgoing.rs: updateEndpointState and unmute links; `publish_mute` posts the endpoint state, or the unmute request while the meeting has us muted.
- backend: follows our server mute from roster updates (mutes locally; opens the mic once a requested unmute lands, then posts the endpoint state); tiles, People pane and Mute all use `muted`.

Tests: roster unit tests (Teams' rule, own server mute), endpoint state body; live with Teams web guests both ways.
<!-- SECTION:FINAL_SUMMARY:END -->
