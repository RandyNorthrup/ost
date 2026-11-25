---
id: TASK-0315
title: 'Security: test hooks are not in release builds'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). A calendar test hook runs JavaScript supplied through local launch flags. The desktop test harness flags (screenshots, scripted actions, JS injection) are for development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test-harness flags and any code that runs caller-supplied JavaScript are compiled only with a dev/test cargo feature that release packages don't enable
- [ ] #2 Release builds ignore or reject those flags, checked in CI
<!-- AC:END -->
