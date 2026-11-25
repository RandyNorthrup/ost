---
id: TASK-0318
title: 'Security: dependency audit in CI'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:25:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The audit noted three RustSec exceptions (unmaintained crates) and no full dependency audit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CI runs cargo audit (and cargo deny for licenses/sources) on every push and fails on vulnerabilities; each remaining exception is justified in config with a review date
- [ ] #2 Unmaintained crates with maintained replacements are replaced
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. deny.toml (advisories incl. unmaintained, licenses, sources, bans) and a CI job running pinned cargo-deny 0.22.1 + cargo-audit 0.23.0 (SHA-256 checked) on every push/PR
2. Fix the open vulnerability (url 2.5.8 -> 2.5.9, RUSTSEC-2026-0592)
3. Re-check the three zbus exceptions (still required by ksni and the keyring store) with reasons and review dates in deny.toml and .cargo/audit.toml
4. chrono (RUSTSEC-2026-0543, new) has a maintained replacement (jiff) but is a ~50-file port: dated exception + follow-up task
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- deny.toml + CI "Dependency audit" job: pinned cargo-deny 0.22.1 and cargo-audit 0.23.0 release binaries, SHA-256 checked; runs on every push to main and every PR (ci.yml triggers)
- cargo audit found RUSTSEC-2026-0592 (url 2.5.8, stack overflow in Url::origin on nested blob: URLs): updated to 2.5.9; cargo-sources.json regenerated with the pinned generator
- zbus 5 exceptions kept: ksni 0.3.7 and zbus-secret-service-keyring-store 1.0.1 (latest) require zbus 5; notify-rust 4.19 moved to zbus 6, but that alone removes nothing. Reasons + review date 2027-02-25 in deny.toml and .cargo/audit.toml
- New: RUSTSEC-2026-0543 chrono unmaintained (2026-09-14), replacement jiff. ~50 files/~400 references; port changes wire formats and local-time math, so split into TASK-0319 with a dated exception (review by 2027-01-31). AC #2 stays open until TASK-0319 lands
- publish = false on the three workspace crates (cargo deny treats unpublished path deps correctly)
- Local: pinned cargo-deny and cargo-audit pass (advisories, bans, licenses, sources ok)
<!-- SECTION:NOTES:END -->
