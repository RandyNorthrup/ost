---
id: TASK-0217
title: Town hall attendees, webinars and event extras as Teams
status: To Do
assignee: []
created_date: '2026-11-17T06:06:00Z'
updated_date: '2026-11-19T05:59:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0184 left (docs/spec/town-halls-and-webinars.md):
- Town hall attendees: Teams streams the event from a service bot in the meeting and plays it in its own player; OST's attendee join gets no answer. The service bot ("s04-prdnoamcompsvc") shows on OST's stage and in People; Teams' rule for hiding it isn't traced.
- Webinars run live; OST's own Publish and Join on the event page; the attendee staging screen and post-end alert live; Bring on screen with a second presenter.
- Not built: "On with preview", Preview as attendee and Join as Organizer / Presenter, Calendar > New > Webinar / Town hall, Copy embed code, Show event in Events app, the published card's Live badge, Join and share; the Start / End buttons' and Live pill's measured styling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Town hall attendees watch the event in OST as in Teams, and the service bot is hidden as Teams hides it
- [ ] #2 Webinars are scheduled, joined and run in OST, checked live
- [ ] #3 The event extras listed above work and look as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-18 (agent TASK-0217): measured Teams desktop on winpc over CDP as town hall attendee, organizer and webinar attendee; spec §7 in docs/spec/town-halls-and-webinars.md.
- Town hall attendees: streaming mode from the roster (`stream` on our endpoint), the composition bot's HLS stream (fMP4, AES-128, key with the bare keyAuthorizationToken) played natively via calling::live_stream (loopback proxy + Qt Multimedia, LiveStreamPlayer.qml); verified live: OST Test 2 played OST TEST 217 town hall 2 (player playing, stream shot att4-event-stream-30.png).
- Composition bot hidden by Teams' blacklistedBots list (+ botData.hiddenParticipant).
- streamingClient bar layout, Waiting/Live/Ended pill and Start event/End event as measured; Preview as Attendee + Join as Organizer/Presenter split (participationPreferences attendee); Calendar New > Webinar/Town hall; published dialog (card preview, Show event in Events app = PATCH isDiscoverable with eTag, Copy embed code); card Live / in N mins badges and Join.
- Webinar OST TEST 217 webinar run live: OST Test 2 organized in OST (start/end), OST Test 3 presenter in OST, ost-test1 attended in Teams (LIVE, then "The event has concluded. Thank you for attending."). All three test events cancelled.
<!-- SECTION:NOTES:END -->
