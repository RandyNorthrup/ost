---
id: TASK-0376
title: Search suggestions show personal-account names
status: Done
assignee:
  - '@t371'
created_date: '2026-11-28T00:04:00Z'
updated_date: '2026-11-28T03:02:00Z'
labels:
  - desktop
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0366 (PR #62): in the new search suggestions, a message whose other person is a personal (8:live:) account shows that person's raw Teams ID in its where line. TASK-0289 (PR #68) added the 8:live: name lookup (fetchTflProfiles); use it in src/api/autosuggest.rs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Search suggestions show the personal-account person's display name (and picture where shown), as Teams does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Check what Teams desktop shows for a message with a personal (8:live:) account (winpc, ost-test1).
2. autosuggest: collect 8:live: people named only by their MRI (messages' ToPreview, chats' members); backend resolves them with directory::tfl_profiles before arranging; arrange names them (where line, chat titles).
3. Unit test; live check on testpc1.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams desktop itself (winpc 26304, ost-test1, 2026-11-27, "289" and is:Messages) shows the raw 8:live:.cid.ca2738c364862c6 in the where line of "OST (You): OST TEST 289 work reply to personal" (ToPreview [{DisplayName: "8:live:…"}]) and only initials (O2) for OST Personal 2's own message. OST now names them as the task asks (fetchTflProfiles), so OST goes past Teams here; where the lookup finds nothing the id stays, as Teams shows it.

- Built: autosuggest::unnamed_people + Names, arrange/arrange_kql name 8:live: people (display_name), backend suggest_names (directory::tfl_profiles, 3 s cap) before arranging; unit test personal_accounts_named.
- Live on testpc1 (t366 = ost-test1): "289" and is:Messages show "OST (You): OST TEST 289 work reply to personal" under OST Personal 2 (Teams desktop shows 8:live:.cid.ca2738c364862c6 there); OST Personal 2's own message shows O2 initials, as Teams (no picture set).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Search suggestions name personal-account (8:live:) people.

Cause: the suggestions service names a Teams free person in a message's ToPreview (and chats' members) by their raw MRI; OST showed it as is. Teams desktop shows the raw id too (winpc, 2026-11-27).

Fix: autosuggest::unnamed_people finds those ids; the backend looks them up with directory::tfl_profiles (TASK-0289's fetchTflProfiles, cached, 3 s cap) and arrange/arrange_kql use the names (display_name). Unknown ids stay as they are. Pictures go through the existing 8:live: photo lookup.

Tests: autosuggest personal_accounts_named. Live: testpc1 (ost-test1) "289" shows OST Personal 2 in the where line.
<!-- SECTION:FINAL_SUMMARY:END -->
