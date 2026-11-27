---
id: TASK-0339
title: 'People app: Add to contacts picker, Sort and Find a contact as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T17:05:00Z'
updated_date: '2026-11-27T00:51:00Z'
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
- [x] #1 Add contact, Sort, Find a contact and the row actions look and behave as Teams' People app, verified on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' People app on winpc (toolbar, Sort menu, Find a contact, columns menu, row actions and menu, Add to contacts picker, Add/Edit contact forms, toasts) and read its code (sort comparator, keyword filter, picker request, add body).
2. api::contacts: picker search (searchV2 source=allTrue), typed numbers, Teams' add body, edit, speed dial, categories; backend contacts_op with Teams' notices.
3. PeopleView: toolbar, header sort, Manage column view, flex columns, hover actions, row menu, Add category flyout, picker, forms, count.
4. Harness --people-test [--people-live]; compare side by side with Teams; remove test contacts.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc 2026-11-26: Teams' People app code (worker): sort comparator dQ (key, then display name; missing keys last), keyword filter dO/dN (name, emails, numbers, substring), header toggleColumnSort (Contact info = EMAIL_ADDRESS), date fields flip order words; picker = searchV2 source=allTrue plus the typed number (keypad letters); add body captured; edit = stored contact with entries marked Post/Patch/Delete; tags = other tags + this one (Delete carries the tag id); speed dial = systemTag "Favorites".
- Built: api::contacts (search_people, typed_number, picked_body/add_picked, edit_body/edit, set_speed_dial, category_body/set_category, profile names for unnamed contacts), backend contacts_op with Teams' notices, PeopleView rewrite, harness --people-test [--people-live].
- Live on linuxlt: geometry, sort, find and picker match Teams; live add/speed dial/favorite/category/edit/delete all confirmed from the service; test contact removed (Teams' local store also cleaned on winpc).
- PR #26.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The People app now works like Teams': Add contact is Teams' "Add to contacts" picker, and the list has Sort, Find a contact, sortable columns, Manage column view and Teams' row actions.

Changes:
- Picker ("Type a name or number"): Teams' searchV2 (source=allTrue). The typed text is also read as a number (keypad letters; "+1 555-123-4567", External). Names show the typed words in bold, the address name in capitals, and Guest.
- Add opens the Add contact form (the directory's name and email are fixed; a number needs a first name). Save posts Teams' exact body.
- Sort: First name, Last name, Company, Recently added; A to Z / Z to A, or New to Old / Old to New. Uses Teams' comparator, with Teams' icons and label.
- Find a contact: name, email or number, 500 ms after typing; no-match state.
- Columns: header sort (Contact info sorts by email) with ↑ / ↓; Manage column view (Categories, Company, Office location); Teams' widths (Name at least 260); All contacts count.
- Rows: hover star, Chat, Audio call, More options (Edit, favorites, speed dial, Add category ▸ with "Create new category", Chat, Audio call, Email, Delete). Notices: "Contact saved.", "Contact deleted.", "Added to speed dial.".
- Edit and category changes use Teams' resolver bodies: entries marked Post/Patch/Delete; the other tags kept; a removal carries the tag's id.
- A contact Teams added without a name of its own shows the profile name.
- Harness `--people-test [--people-live]`; docs/desktop.md.

Tests: unit tests from the captures (picker body, numbers, edits, tags, profile names). Live as ost-test1 against Teams on winpc:
- Geometry, sort, find and picker results match.
- Live add, speed dial, favorite, category add/remove, Edit (Company) and delete, all confirmed from the service. The test contact was removed.

Unverified: the Phone field's type ("Mobile") and a new category's colour ("DEFAULT").

PR #26.
<!-- SECTION:FINAL_SUMMARY:END -->
