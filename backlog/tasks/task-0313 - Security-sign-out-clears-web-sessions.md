---
id: TASK-0313
title: 'Security: sign-out clears web sessions'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:16:00Z'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Per-profile web storage name (ost-apps, ost-apps-<profile>) from the backend.
2. Sign-out writes a marker and restarts OST; at start, before Qt WebEngine initializes, the profile's storage (data dir with cookies/local storage/IndexedDB/service workers, and its HTTP cache) is removed.
3. Docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified (main @ 575e4404): desktop/qml/Main.qml:46 one WebEngineProfilePrototype storageName "ost-apps" with ForcePersistentCookies for every OST_PROFILE (on linuxlt all profiles share ~/.local/share/OST/QtWebEngine/ost-apps); desktop/src/backend.rs:10621 sign_out only cleared tokens (auth::sign_out), never web cookies/storage.
<!-- SECTION:NOTES:END -->
