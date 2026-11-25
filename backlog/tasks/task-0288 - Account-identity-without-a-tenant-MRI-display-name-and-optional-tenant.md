---
id: TASK-0288
title: 'Account identity without a tenant: MRI, display name and optional tenant'
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0287
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST assumes every account is a work account: it builds 8:orgid: IDs in about 75 places and reads oid, tid, name and upn from the access token. Personal accounts have 8:live: IDs, no tenant and opaque access tokens. Make the signed-in account's identity an abstraction that both kinds fill in, without changing what work accounts see.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The signed-in user's MRI, object ID, tenant (optional) and display name come from one account identity, not from parsing the access token at each call site
- [ ] #2 No code builds an 8:orgid: MRI from a bare object ID outside the identity module
- [ ] #3 Work-account sign-in, chat, calls, calendar and files behave exactly as before (desktop and teams-cli tests pass; live check with ost-test1)
<!-- AC:END -->
