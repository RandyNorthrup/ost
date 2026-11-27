---
id: TASK-0318
title: 'Security: dependency audit in CI'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-27T12:51:00Z'
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
- [x] #2 Unmaintained crates with maintained replacements are replaced
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

- 2026-11-27 (AC #2): chrono was replaced by jiff in TASK-0319 (Cargo.lock has no chrono; cargo-sources.json lists jiff 1.0.3), and its dated exception is already gone from deny.toml and .cargo/audit.toml.
- Pinned cargo-deny 0.22.1 and cargo-audit 0.23.0 (release binaries, SHA-256 checked as in ci.yml) on linuxlt against main + this branch: "advisories ok, bans ok, licenses ok, sources ok"; cargo audit scanned 610 crates with no vulnerabilities and no warnings outside the ignore list.
- The only unmaintained crates left are zvariant, zbus_names and zvariant_derive (RUSTSEC-2026-0370/0371/0372): standalone crates zbus 6 merged in. No replacement can be made from OST's side: ksni 0.3.8 (released 2026-11-26) and zbus-secret-service-keyring-store 1.0.1 (latest) still depend on zbus ^5, and moving OST's own D-Bus code to zbus 6 would add zbus 6 beside zbus 5 without removing them. Recorded in deny.toml (checked 2026-11-27, review by 2027-02-25).

- PR #40: CI (build/test, clippy, format, dependency audit, release-build harness check, CodeQL) all passed; Codex code and security review: no findings.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI now audits every dependency on every push and pull request, and the unmaintained crates that had maintained replacements are gone.

Changes:
- deny.toml (advisories incl. unmaintained, licenses, sources, bans) and a "Dependency audit" CI job running pinned cargo-deny 0.22.1 and cargo-audit 0.23.0 (SHA-256 checked); it fails on any vulnerability.
- url 2.5.8 -> 2.5.9 for RUSTSEC-2026-0592.
- chrono (RUSTSEC-2026-0543, unmaintained) replaced by jiff in TASK-0319; its dated exception is removed.
- The three remaining exceptions (zvariant, zbus_names, zvariant_derive: merged into zbus 6) carry reasons and a review date (2027-02-25) in deny.toml and .cargo/audit.toml. They stay until ksni and keyring's Secret Service store move to zbus 6; rechecked 2026-11-27 (ksni 0.3.8, keyring store 1.0.1 still on zbus 5).

Tests:
- Pinned cargo deny --locked check advisories licenses sources bans: all ok.
- Pinned cargo audit: no vulnerabilities (610 crates).
- CI's Dependency audit job on the PR.
<!-- SECTION:FINAL_SUMMARY:END -->
