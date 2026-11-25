---
id: TASK-0318
title: 'Security: dependency audit in CI'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The audit noted three RustSec exceptions (unmaintained crates) and no full dependency audit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI runs cargo audit (and cargo deny for licenses/sources) on every push and fails on vulnerabilities; each remaining exception is justified in config with a review date
- [ ] #2 Unmaintained crates with maintained replacements are replaced
<!-- AC:END -->
