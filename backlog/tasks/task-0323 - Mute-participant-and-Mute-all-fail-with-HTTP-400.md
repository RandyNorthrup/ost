---
id: TASK-0323
title: Mute participant and Mute all fail with HTTP 400
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T02:23:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). In a meeting, muting a participant and Mute all fail with HTTP 400.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Organizers and presenters can mute one participant and mute all as in Teams, verified live between test accounts against Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find OST's mute requests (outgoing.rs mute_participant / mute_all) and Teams' own (calling-pluginless muteAsync, calling-roster Mute all dialog)
2. Capture what Teams sends for Mute participant and Mute all in a live meeting
3. Send the same body, callback and headers; handle the reply and the muteUnmuteAsync result; mark the people muted at once
4. Live check on linuxlt between ost-test1 (organizer), OST Test 2 and OST Test 3, with Teams on winpc watching
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Cause: OST sent muteParticipants as bare MRI strings; the service takes {"id": mri} objects and refuses anything else with HTTP 400. Mute all's body already had the right shape. The new requests return 202 for both.
- Teams desktop on Windows sends these from SlimCore (native code), so the WebView2 network log shows nothing. Captured instead from Teams on the web (OST Test 2 signed in on linuxlt with fake media): the same body plus links.clientCallback (trouter .../callAgent/<endpoint>/<operationId>/conversation/muteUnmuteAsync/) and operationId, because ECS enableAsyncMute is on. The reply is 202 {"muteUnmuteResponse":{}}, and the result comes to the callback.
- Teams' Mute all dialog is a plain confirm ("Mute everyone?") with no option about unmuting.
- Found live: after Mute all, the service mutes people who join later. OST missed it because that rosterUpdate arrives before the join completes. It is now kept and applied once the join shows.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
In meetings, Mute participant and Mute all now work as in Teams.

Cause: OST named the participant to mute as a bare MRI string ("muteParticipants": ["8:orgid:…"]). The conversation service only takes {"id": …} objects and refused the request with HTTP 400.

Changes:
- Mute participant and Mute all send exactly what Teams sends. Both POST to the conversation's mute link with `from` (id, displayName, endpointId, participantId, languageId), scope "specified" or "all", muteParticipants as {id} objects ([] for Mute all), mediaTypes ["audio"], a muteUnmuteAsync clientCallback and an operationId. They carry the call's headers (chain and message ids, client, partition, region, ring).
- The 202 reply and the result pushed to the callback (muteUnmuteResponseAsync) mark the muted people's audio as server-muted at once, as Teams does, before the roster update arrives.
- Joining a meeting where Mute all is still in force: the rosterUpdate that mutes us can arrive before the join completes. OST now keeps it and applies it once the join shows, so it joins muted with "You've been muted", as Teams does.
- Mute all's dialog was already Teams' ("Mute everyone?", no option about unmuting).
- docs/spec/call-and-meeting-window.md documents the wire format, the async result and the joiner rule. Main.qml gains a --join-mute-test harness.

Live check (linuxlt; ost-test1 organizer, OST Test 2 and OST Test 3 on virtual mics; Teams desktop on winpc as ost-test1):
- Mute participant on OST Test 3: 202, then the callback said 1 muted. OST Test 3 logged the meeting's mute and its mic went off.
- Mute all: 202, then the callback said 2 muted. OST Test 2 was muted too.
- Teams on winpc showed both muted, with Mute participant greyed out for them.
- OST Test 3 rejoining while Mute all was in force joined muted, matching Teams.
- Teams' own requests were captured from Teams on the web (OST Test 2, fake media).

Tests: unit tests for the request body, the callback URL, and the reply and async result parsing (outgoing.rs), and the roster marking (roster.rs). The full suite runs in CI.
<!-- SECTION:FINAL_SUMMARY:END -->
