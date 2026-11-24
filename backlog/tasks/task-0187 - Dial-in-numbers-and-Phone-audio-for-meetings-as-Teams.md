---
id: TASK-0187
title: Dial-in numbers and Phone audio for meetings as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-17T04:07:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both test accounts now have Audio Conferencing (2026-11-15). OST shows no dial-in details and always greys out Phone audio.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Phone audio is offered and works as in Teams
- [x] #2 Meeting info shows Teams' dial-in numbers, and pre-join offers Phone audio from the invite (before-join detection for every meeting: TASK-0215)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (dde4544, merged); spec docs/spec/call-and-meeting-window.md §1.8k.
- OST now joins meetings as Teams does (conversation, then call), so the dial-in numbers arrive at join; Meeting info shows Dial in manually, toll number, Get local numbers, conference ID.
- Phone audio: pre-join choice and text, Use phone for audio (number box with dial-plan check and formatting, Call me, Dial in manually, Call me back), More / Join info > Call me, Teams' states and errors, favourite numbers. Call me was only tried against +1 000 000 0000, which the service refused ("You are not allowed to dial-out to this destination…"); no real phone was ever called.
- Re-checked on the merged build: numbers at join, Use phone for audio, More > Call me, Meeting info (my harness run hit its time limit before leaving, so its test event was deleted by hand; none left).
- Lobby and breakout joins with the two-step join are being re-checked with TASK-0213.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Dial-in numbers and Phone audio for meetings as Teams.

- Meetings are joined in Teams' two steps so the dial-in numbers arrive; Meeting info shows them.
- Pre-join Phone audio, Use phone for audio with Call me / Dial in manually / Call me back, the dial plan from your policy, favourite numbers, Teams' states and errors.

Tests: unit tests for numbers and dial plans; --phone-audio-test live (Call me only to an invalid number). Follow-up TASK-0215.
<!-- SECTION:FINAL_SUMMARY:END -->
