---
id: TASK-0333
title: People app contacts fail with HTTP 403
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T17:05:00Z'
labels:
  - bug
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The People app's contacts request fails with HTTP 403.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The People app loads contacts the way Teams does for the same account (correct endpoint and token), verified against Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find how Teams' People app loads contacts (winpc worker code, IndexedDB store).
2. Move api::contacts to the contacts v3 service (GET/POST/PATCH/DELETE {mt}/beta/contactsv3/ with the Teams token), favorites = SfbFavorites tag, categories = tags, first-name order.
3. People list columns as Teams (Name, Contact info, Company, Office location).
4. Unit tests from the store; live check vs Teams on winpc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc 2026-11-26: Teams' People app reads its capiv3 contacts store, synced from the middle tier's contacts v3 service ({mt}/beta/contactsv3/?pageSize=200, Teams token, worker module 59660); favorites are the "SfbFavorites" system tag, categories the contacts' tags; first-name order. OST used Graph beta /me/contacts, which its token can't read (403).
- Fix: api::contacts on contacts v3 (list with paging, POST add, PATCH favorite with Teams' systemTags body, DELETE); PeopleView columns as Teams (Name, Contact info, Company, Office location; star; picture by MRI).
- Live on linuxlt: --apps-test lists Randy Northrup (Randy@scnetsolutions.com, 8057942764) as Teams' People app does on winpc; the service rejects defaultEmail without an MRI, so a typed contact keeps its email in emails.
- Teams' Add contact is an "Add to contacts" people picker, not OST's form; follow-up task.

- --apps-test (final build): add → favorite (SfbFavorites) → delete all work against contacts v3; the test contact (@example.com) is gone.
<!-- SECTION:NOTES:END -->
