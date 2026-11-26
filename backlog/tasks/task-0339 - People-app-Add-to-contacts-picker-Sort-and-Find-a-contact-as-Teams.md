---
id: TASK-0339
title: 'People app: Add to contacts picker, Sort and Find a contact as Teams'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T17:05:00Z'
updated_date: '2026-11-26T20:48:00Z'
labels:
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0333 moved the People app to Teams' contacts v3 service. Teams' Add contact is an "Add to contacts" picker (Type a name or number) that adds a directory person (mri, webAccounts) or a phone number; its list has Sort (First name …), Find a contact, the column view menu, the All contacts count and the row's Chat / Audio call / More options. OST still has its own form and a plain list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Add contact, Sort, Find a contact and the row actions look and behave as Teams' People app, verified on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' People app on winpc (toolbar, Sort menu, Find a contact, columns menu, row actions and menu, Add to contacts picker, Add/Edit contact forms, toasts) and read its code (sort comparator, keyword filter, picker request, add body).
2. api::contacts: picker search (searchV2 source=allTrue), typed numbers, Teams' add body, edit, speed dial, categories; backend contacts_op with Teams' notices.
3. PeopleView: toolbar, header sort, Manage column view, flex columns, hover actions, row menu, Add category flyout, picker, forms, count.
4. Harness --people-test [--people-live]; compare side by side with Teams; remove test contacts.
<!-- SECTION:PLAN:END -->
