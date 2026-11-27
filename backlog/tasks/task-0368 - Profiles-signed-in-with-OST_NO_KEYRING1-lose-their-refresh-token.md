---
id: TASK-0368
title: Profiles signed in with OST_NO_KEYRING=1 lose their refresh token
status: To Do
assignee: []
created_date: '2026-11-27T18:19:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the 2026-11-27 parity audit (side finding): after signing in a new profile with OST_NO_KEYRING=1, Calendar, search, presence and other services failed with 'Token expired and no refresh token'. The profile's config recorded tokens_in_keyring = true although the keyring wasn't used; restarting without the variable fixed it. Details: /home/randy/.local/share/ost-remaining/audit/auditA.md, side findings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A profile signed in with OST_NO_KEYRING=1 keeps working across token expiry and restarts (tokens stored and read where the config says they are), with a regression test
<!-- AC:END -->
