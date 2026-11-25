---
id: TASK-0319
title: Replace chrono (unmaintained) with jiff
status: To Do
assignee: []
created_date: '2026-11-25T20:24:00Z'
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
