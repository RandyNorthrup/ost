---
id: TASK-0216
title: Organizer joining a breakout room fails after the two-step join
status: Done
assignee:
  - '@claude'
created_date: '2026-11-17T04:26:00Z'
updated_date: '2026-11-17T06:54:00Z'
labels:
  - desktop
  - bug
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression from TASK-0187's two-step meeting join (conversation, then call), found during TASK-0213: in --breakout-test --breakout-join (OST Test 2's own meeting), the conversation join and call request succeed, then the server ends it with "Conversation ending after breakout room is not open. (403)". OST shows "Couldn't join the meeting" and closes the call window although it had just returned to the main meeting; the room's call acceptance arrives after OST gave up, so that leg may dangle. The same flow worked before (TASK-0111, 2026-11-11).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An organizer and a participant join and leave breakout rooms as in Teams, with the two-step join, verified with Teams on winpc
- [x] #2 A failed room join never closes the main meeting's window or leaves a call leg behind
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Fixed by a subagent (52943f9, merged): Teams joins rooms in two steps too; the 403 / 5745 means the room isn't open. OST mishandled that failure. Now each join has its own callback tag and only accepts its own answer; a late acceptance after a failure is hung up (watched 30 s); a failed call's events can't end the meeting you're in; a failed call request leaves the conversation; the organizer's held main meeting resumes with Teams' "You don't have access to this room" text; a participant keeps its meeting (media held during the move, then resumed).
- Also fixed: mute state now carries into a room and back (OST was arriving unmuted: a privacy issue).
- Live with Teams desktop on winpc: organizer and participant join, leave, rooms closing, return to main; failed joins (never-opened and ended rooms) keep the meeting; plain join and lobby admission re-checked; all rooms deleted, both sides confirmed out. Rebased on the town hall commit and re-run.
- Leftovers: TASK-0218.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Breakout rooms work again with the two-step join, and a failed room join never closes the meeting or leaves a call leg.

- Join answers matched to their own call; late legs hung up; failed calls can't affect the current meeting; Teams' error text.
- Mute state carries into rooms and back, as Teams.

Harness: --breakout-manual, --breakout-wait, --breakout-join-unopened, --breakout-watch-rejoin. Follow-up TASK-0218.
<!-- SECTION:FINAL_SUMMARY:END -->
