---
id: TASK-0316
title: 'Security: pinned, verified release toolchain and provenance'
status: To Do
assignee: []
created_date: '2026-11-25T19:49:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The AppImage build runs tools from mutable releases without verifying a signature or hash; the Flatpak job runs a generator fetched from a moving branch and installs unpinned Python dependencies; checksums alone don't establish provenance.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every tool the release and CI workflows download is pinned to an exact version and verified by SHA-256 (or signature) before it runs; GitHub Actions are pinned to commit SHAs
- [ ] #2 Python dependencies for build tools are pinned with hashes (pip --require-hashes)
- [ ] #3 Releases publish GitHub build-provenance attestations (Sigstore) for every file, and the wiki explains how to verify them with gh attestation verify
- [ ] #4 A test pre-release tag builds all packages successfully with the pinned toolchain
<!-- AC:END -->
