---
id: TASK-0349
title: >-
  Camera fails right after a lobby admission (media descriptions go to the old
  call leg)
status: Done
assignee:
  - '@lobbycam'
created_date: '2026-11-27T08:07:00Z'
updated_date: '2026-11-27T11:25:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0342's native-format test (2026-11-27). After a meeting's organizer admits OST from the lobby, the media processor moves the call (participant retarget). OST's first camera toggle then posts UpdateMediaDescriptions to the pre-move link and gets HTTP 406, code 481 subCode 10021 "Call is ended" (detail 10109 "Participant retarget was successful"). OST shows "Your camera failed". A later toggle, after another re-offer, succeeds. Teams desktop turns its camera on at once after admission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After a lobby admission, turning the camera on works the first time, verified live
- [x] #2 UpdateMediaDescriptions follows the call's current link after a retarget
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce live: OST Test 3 held in the lobby of an OST Test 2 meeting (lobby OrganizerOnly), admitted by --join-admit-each, camera on at a set delay after admission (--join-lobby-camera=<ms>), trouter dumps for the event order.
2. Track the leg move from the admission to the retarget acknowledgement; a media description the old leg refuses meanwhile is owed to the new leg.
3. On the retarget, move every leg link (call leg, hold, transfer, replacement, re-offers, media descriptions) and describe our camera/screen to the new leg when one is sending or a description is owed.
4. Unit tests; live re-check at the failing delay and at once; restore the lobby setting and delete the meeting.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Reproduced live 2026-11-27 (meeting "OST TEST 349", organizer OST Test 2, AutoAdmittedUsers OrganizerOnly): with the camera turned on 1.1 s after admission, the toggle waited for the move answer, posted UpdateMediaDescriptions to the old leg 150 ms after it and got 406 code 481 subCode 10021 "Call is ended."; the retarget acknowledgement came 75 ms later. Status "Your camera failed", camera off.
- Event order (trouter dumps): admission conversationUpdate 28.51 s, move offer (newOffer true) 29.32 s, our answer 29.77 s, retarget mediaAcknowledgement (subCode 10109) 30.13 s with the new leg's links. Turned on at once (before the move), the description reached the old leg in time.

- Fix (outgoing.rs LegMove; backend leg_retarget handler): the admission starts the leg move and the retarget acknowledgement ends it. A description the old leg refuses meanwhile is owed to the new leg instead of failing the camera. The retarget now also takes the new leg's replacement link (with callLeg, hold, transfer, mediaRenegotiation, updateMediaDescriptions), then describes our camera and screen to the new leg when one is sending or a description is owed (the processor knows our lines by its new mids after the move).
- Harness: --join-lobby-camera[=<ms>] with --join-lobby-wait turns the camera on that long after admission and logs JOIN lobby-camera lines.
- Verified live 2026-11-27 (OST Test 3 by link into "OST TEST 349", admitted by OST Test 2, virtual mic ost_lobbycam_mic, test camera C /dev/video22):
  - 1.8 s: the old leg answered 406 "Call is ended.", the description waited, the retarget came 2 ms later, the new leg answered 200; camera on, no "Your camera failed"; the organizer received OST Test 3's camera (MCP source result ok, frames decoded).
  - At once, 1.1 s and 2.4 s: 200 on the old leg (before the move) or the new leg (after it), and each time the new leg was described again after the retarget (200).

- Codex review: a share the moved leg isn't told about stops as well, with "Couldn't share your content" (a3fd3b6f), as offer_capture's failure path. Codex is clean on a3fd3b6f.
- Cleanup: lobby bypass restored to EveryoneInCompany and read back, "OST TEST 349" deleted, test camera feed, mic watcher and virtual mic removed. The watcher never saw a stream on the built-in mic.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The camera now turns on the first time right after a lobby admission, as it does in Teams desktop.

Cause: when the lobby admits you, the service moves your call leg to the meeting's call (participant retarget). The old leg ends when the move answer is taken, but the new leg's links only arrive with the retarget acknowledgement a few ms to about 1 s later. A camera turned on in that window posted UpdateMediaDescriptions to the old leg and got 406 "Call is ended." (481/10021), so OST showed "Your camera failed".

Changes:
- `OutgoingCall` tracks the leg move (`LegMove`) from admission to retarget. If the old leg refuses a media description during the move, the description is held for the new leg and the camera stays on.
- `retarget()` moves every leg link OST uses: call leg, hold, transfer, re-offers, media descriptions, and now `replacement`. It reports when the new leg must be told: a description is owed, or the camera or screen is sending (the processor's mids change with the move). The backend then posts the description. If that post fails, the camera or share stops with Teams' messages.
- Harness `--join-lobby-camera[=<ms>]` (with `--join-lobby-wait`). Spec notes in call-and-meeting-window.md.

Tests:
- Unit tests: `descriptions_refused_while_the_leg_moves_go_to_the_new_leg`, plus the extended `a_retarget_gives_the_new_leg` (with the replacement link).
- Live on linuxlt: OST Test 3 admitted by OST Test 2. The bug reproduced before the fix. After the fix, a 406 during the move was held and posted to the new leg (200), with no error, and the organizer received the camera. Turning the camera on at once, at 1.1 s and at 2.4 s also worked.

PR #39.
<!-- SECTION:FINAL_SUMMARY:END -->
