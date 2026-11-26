---
id: TASK-0335
title: 'Sign-language model downloads back off after failures (issue #14)'
status: Done
assignee:
  - '@issues'
created_date: '2026-11-26T15:10:00Z'
updated_date: '2026-11-26T17:08:00Z'
labels:
  - bug
  - calls
  - github-issue
dependencies: []
references:
  - https://github.com/RandyNorthrup/ost/issues/14
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #14 (static review of v0.3.0): when sign language detection still needs its model, a failed preparation clears the in-flight flag and the next 500 ms tick starts another attempt, so a fast failure causes repeated requests and warnings while the feature stays on (desktop/src/backend.rs around L14920 and L16454 at bedf384d).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Failed model preparations retry with a bounded, growing backoff instead of every 500 ms; the backoff resets after a success or when the user turns the feature off and on again
- [x] #2 Downloads stay one at a time with the pinned hash check; a unit test simulates repeated failures without contacting the model host
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. sign_detection: a Retry state (one attempt at a time; after a failure wait 5 s doubling to 5 min, up to 20% jitter off; reset on success or Signer turned on again).
2. Split the download into a fetcher and a verified cache-or-fetch step with the pinned hash, so a test can pass a fake fetcher.
3. Desktop tick uses Retry; set_sign_language_state resets it when Signer is turned on again.
4. Unit tests: repeated fake failures over simulated 500 ms ticks, wrong-hash bytes rejected, reset, success.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed at 8722149f (issue text treated as a report, checked in code):
- desktop/src/backend.rs:14930-14938: sign_detection_tick sets sign_model_loading, spawns sd::prepare, and clears the flag whatever the result, so the next tick starts another attempt.
- desktop/src/backend.rs:16464-16476: the tick runs every 500 ms while a Signer.
- src/calling/sign_detection.rs:303-321 prepare: BUSY mutex (one at a time); hash checked in read_cached (195-206) and download (269-276).
- Other first-use models: voice isolation (desktop/src/backend.rs:29441-29473) prepares only on a user action (noise suppression settings), no timer, so no retry loop; the video-effects model is embedded (vfx/src/lib.rs:19); recognition (TASK-0153) uses Teams' biometric service, no download. Only sign detection has the pattern.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sign language detection no longer retries a failed model download every 500 ms (issue #14).

Cause: the desktop's 500 ms sign detection tick cleared its in-flight flag after a failed `prepare`, so the next tick started another download at once while Signer mode stayed on.

Changes:
- `src/calling/sign_detection.rs`: new `Retry` (one attempt at a time; after a failure the next waits 5 s, doubling up to 5 min, made up to a fifth shorter at random; reset on success or `reset()`). The download is split into a network fetcher and `model_bytes`, which reads the verified cache or fetches, checks the pinned SHA-256 and writes atomically; `prepare` keeps its BUSY mutex and uses them.
- `desktop/src/backend.rs`: the tick asks `Retry` before preparing and records success or failure (the warning now says how many failures and when it retries); turning Signer on again resets the backoff.
- Other first-use models checked: voice isolation only prepares on a user action, the video-effects model is embedded, recognition has no download, so none had the loop.

Tests:
- `sign_detection_failed_model_downloads_back_off`: ten minutes of 500 ms ticks against a fake fetcher that always fails gives 7-8 attempts with growing, bounded gaps; wrong-hash bytes fail and aren't kept; reset and success start over; a cached model is used without fetching. No network.
- `sign_detection_retry_waits_grow_to_their_bound`.
- `cargo test -p teams-cli --lib -- sign_detection feedback` on linuxlt: 13 passed. Desktop build with test-harness clean.

Not verified live: a failing download in a real meeting (covered by the unit test).
<!-- SECTION:FINAL_SUMMARY:END -->
