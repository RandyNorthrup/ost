---
id: TASK-0313
title: 'Security: sign-out clears web sessions'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). Web cookies persist, and the sign-out path doesn't explicitly clear them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Signing out deletes the account's WebEngine cookies, local storage, IndexedDB, cache and service workers for every profile OST uses (sign-in, hosted apps, Loop, viewers), and the next sign-in starts clean
- [ ] #2 Each OST profile (OST_PROFILE) keeps its own web storage, so accounts never share cookies
<!-- AC:END -->
