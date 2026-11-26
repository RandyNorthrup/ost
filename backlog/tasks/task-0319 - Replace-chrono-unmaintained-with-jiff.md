---
id: TASK-0319
title: Replace chrono (unmaintained) with jiff
status: In Progress
assignee:
  - '@time'
created_date: '2026-11-25T20:24:00Z'
updated_date: '2026-11-26T12:49:00Z'
labels:
  - security
  - dependencies
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RUSTSEC-2026-0543 (2026-09-14) declares chrono unmaintained, with jiff and time as the recommended replacements. OST uses chrono directly in about 50 files (engine and desktop: ~400 references - RFC 3339 parsing with offsets, local-time formatting, durations, calendar math, tests). TASK-0318's dependency audit lists it as a dated exception in deny.toml until it is replaced. jiff fits best: it has real time zone support (time's local offset is unavailable in multithreaded programs on Linux). The port changes wire formats in places (chrono's to_rfc3339 writes +00:00 where jiff writes Z) and local-time math (calendar days vs 24-hour spans), so it needs its own review and a full test pass.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 chrono is gone from Cargo.lock; time handling uses jiff
- [ ] #2 Every timestamp OST sends to Teams/Graph keeps its current format (RFC 3339 shape, offset, fractional digits), covered by tests
- [ ] #3 Local-time displays (chat, calendar, presence, recaps) render as before, including across DST changes
- [ ] #4 The RUSTSEC-2026-0543 exception is removed from deny.toml and cargo deny passes
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read every chrono use (55 files) and chrono 0.4.45's own parser/local-time code to know the exact behavior to keep.
2. Baseline tests first, against chrono, where coverage was thin (service times to RFC 3339, TUI message times, regional patterns, HID locale payload, presence expiries across DST, recaps' local day bounds); run them under several TZs on linuxlt.
3. Add src/clock.rs: jiff helpers that keep chrono's shapes (RFC 3339 grammar ported from chrono, .000Z millis, +00:00 rfc3339, floor millis, single/earliest wall-time readings).
4. Port every file (engine, desktop, examples) to jiff 1.0.3 through clock; keep 24-hour Duration::days on times and calendar days on dates.
5. Differential harness outside the repo: chrono vs clock over random instants, every DST transition 2000-2060 in 14 zones, 200k fuzzed RFC 3339 strings, wall-clock parsing and date math.
6. Re-run the same TZ test matrix on the port; add explicit-zone DST tests (POSIX TZ strings, no tzdb needed).
7. Drop chrono from Cargo.toml/Cargo.lock, deny.toml and .cargo/audit.toml; regenerate notices and flatpak cargo-sources.
8. Live check on linuxlt (ost-test1): calendar day/week/month + event times, chat timestamps, Activity times, before/after screenshots.
9. PR, CI, Codex review.
<!-- SECTION:PLAN:END -->
