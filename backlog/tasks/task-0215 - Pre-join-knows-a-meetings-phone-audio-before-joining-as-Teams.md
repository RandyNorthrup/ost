---
id: TASK-0215
title: Pre-join knows a meeting's phone audio before joining, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-17T04:07:00Z'
updated_date: '2026-11-17T08:21:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams knows before you join whether Phone audio is available because it quietly joins the call while the pre-join window is open (TASK-0187, docs/spec/call-and-meeting-window.md §1.8k). OST reads the calendar invite's dial-in block instead, so for meetings OST creates (no dial-in block in their invite) Phone audio is greyed out before joining, although dial-in works once in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pre-join offers Phone audio exactly when Teams does, for meetings created by Teams and by OST
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (421a09d, merged): the pre-join joins the meeting's conversation and its call preheated (preheatProperties 1, mic muted, speaker off; invisible to others), decides Phone audio from the details that arrive (meeting capability + invitation, else allowPstnConferencing after 15 s), Join now makes the endpoint visible (updateEndpointState preheat 0, updateEndpointMetadata), Cancel / Escape / close leaves, and the preheat is left after 60 s as Teams does.
- Live: OST-made meeting (Phone audio in 1.6 s), OST Test 2 hosting (never saw the preheat), organizer-only lobby (15 s fallback, then lobby admission with data channel), 60 s expiry, a Teams Meet now; --phone-audio-test passes. Re-checked on the merged build: Phone audio before joining, joined muted, left, test event deleted.
- Merged with the TASK-0216 join changes (duplicate new_call_tag removed). Follow-up TASK-0219.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pre-join preheats the meeting's call as Teams does, so Phone audio is offered exactly when Teams offers it, for meetings made by Teams and by OST; cancelling or timing out leaves nothing behind. Harness --preheat-test. Follow-up TASK-0219.
<!-- SECTION:FINAL_SUMMARY:END -->
