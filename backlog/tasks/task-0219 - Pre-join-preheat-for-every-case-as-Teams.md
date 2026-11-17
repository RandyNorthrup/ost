---
id: TASK-0219
title: Pre-join preheat for every case as Teams
status: To Do
assignee: []
created_date: '2026-11-17T08:21:00Z'
updated_date: '2026-11-17T19:50:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0215 left (docs/spec/call-and-meeting-window.md §1.8k): a channel Meet now pre-join and a pre-join opened while already in a call aren't preheated (they still read the calendar invitation); OST's preheat request keeps its own call modalities and doesn't send mediaDescriptions or aiVoiceConsent, and doesn't acknowledge the acceptance in its Trouter reply as Teams does; Teams desktop's own preheat and its dial-plan ECS flag weren't measured on winpc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every pre-join preheats as Teams does, with Teams' request fields, checked against Teams desktop on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop measured on winpc (MSTeams 26304.1201, 2026-11-17). Its signalling is native (SlimCore), so the preheat was measured through its JS (preheatService.startPreheatingMW, calling-electron's preheatFlags), its ECS and its behaviour: enabled by enableCallPreHeatDesktop (true) + SlimCore >= callPreHeatDesktopMinSlimcoreVersion + SlimCore ECS enablePreheat (true in winpc's slimcore-ecs-cache.data); ost-test1's ECS overrides only joinOngoingMeetingInPreheatedFlow and isStreamingAttendeesPreheatDisabled; enablePreheatWhileCallIsActive true; the dial-plan flag enableDialPlans true, not overridden.
- Teams desktop live: a scheduled meeting's pre-join offered Phone audio at once; a second meeting's pre-join opened while in a meeting was preheated too (Phone audio disabled at open, offered 1.2 s later; Cancel, then Leave); a channel Meet now pre-join is not preheated (no meeting until Start: no channel post, Phone audio stayed disabled for over a minute) - OST already behaves so.
- OST: the preheat request carries Teams' fields (callModalities Audio + ScreenViewer; mediaDescriptions recvonly for the sendrecv video lines only - describing every m-line was refused, 410 InvalidInitialOfferMediaDescriptions / InvalidFinalAnswerMediaDescriptions; participantPropertyBag.aiVoiceConsent; the null contexts); every meeting call carries the property bag. The Trouter acceptance reply's links keep the call's tag; meeting joins no longer POST the acknowledgement (Teams doesn't). A pre-join opened in a call preheats; closing it leaves the preheat.
- Live on linuxlt: --preheat-test --preheat-join (preheated, Join now, stayed 57 s with no acknowledgement POST, left, event deleted); --preheat-test --preheat-cancel --preheat-in-call=<meeting> (preheated while in the first meeting, Phone audio offered in about 2 s, Cancel left the preheat, then the first meeting was left). Lib tests: 699 passed.
<!-- SECTION:NOTES:END -->
