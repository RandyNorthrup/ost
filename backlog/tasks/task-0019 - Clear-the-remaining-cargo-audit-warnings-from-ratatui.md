---
id: TASK-0019
title: Clear the remaining cargo audit warnings from ratatui
status: To Do
assignee: []
created_date: '2026-11-05T03:22:00Z'
labels:
  - security
  - deps
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the 2026-11-04 dependency work, cargo audit reports 0 vulnerabilities and 3 warnings, all through ratatui 0.29: paste (unmaintained, RUSTSEC-2024-0436) and lru 0.12 (unsound, RUSTSEC-2026-0253 and RUSTSEC-2026-0002).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cargo audit reports no warnings, or each remaining one is documented as not reachable
- [ ] #2 The TUI still works after any ratatui upgrade
<!-- AC:END -->
