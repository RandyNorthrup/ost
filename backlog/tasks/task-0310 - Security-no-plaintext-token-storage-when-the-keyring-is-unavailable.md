---
id: TASK-0310
title: 'Security: no plaintext token storage when the keyring is unavailable'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). If the system keyring is disabled or unavailable, access and refresh tokens fall back to a plaintext config file (mode 0600).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Without a working Secret Service keyring, OST doesn't write access or refresh tokens to disk by default; it keeps them in memory and asks to sign in again next start, and Settings explains why and how to enable a keyring
- [ ] #2 Storing tokens in a file needs an explicit opt-in (OST_NO_KEYRING=1 or a setting), is documented as weaker than the keyring, and the file is created 0600 atomically
- [ ] #3 Existing plaintext tokens are moved into the keyring when it becomes available, and the plaintext copy is removed
<!-- AC:END -->
