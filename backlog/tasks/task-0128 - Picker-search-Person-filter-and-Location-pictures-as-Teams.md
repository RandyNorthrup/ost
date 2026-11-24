---
id: TASK-0128
title: 'Picker search: Person filter and Location pictures as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-13T16:48:00Z'
updated_date: '2026-11-20T21:06:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Move/Copy picker search has a Person pill ("Filter by people": a people search popup, "{0} +{1}" when several are chosen, Clear) and shows the site's picture (or the person's) before other sites' Location. Both need measuring on winpc once Teams' substrate search sign-in works again (on 2026-11-13 it showed a "Please sign in" prompt that wouldn't close). Strings and query are in docs/spec/file-actions.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The picker's search has the Person filter as Teams draws it, and choosing people narrows the results
- [x] #2 Location shows a site's or person's picture before their name as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19: Teams' picker search All files still stops at its "Please sign in" (OneDrive's substrate token, client 08e18876, is fetched in a blocked popup); Sign In / Not now / X do nothing. Person filter taken from OneDrive's code (spofilepickerwebpack 283/2490, odsp-web-prod_2026-11-06.005): a 32-tall pill (radius 18, padding 5 14, 600, 1 px stroke; active = brand-2 fill) labelled Person (max one person) with a chevron, or the person's 20 px picture and name; its menu (320-380 wide, radius 8, padding-top 4): a round 32 px "Search for a person" box, rows 32+ (padding 4 8, radius 8; a check slot, 20 px picture, name 14), "Loading people…", "No people found", then a footer with Clear (12/600). Query: QueryString + ' AND (ModifiedBy:"{name}" OR author:"{name}")' plus a People QueryAnnotation.

- 2026-11-20 built: Person pill + menu in the picker search (Graph /me/people), people clause in drive::folder_query, Location pictures (getsitelogo / drive owner); harness --picker-person-test. Pending: run.

- 2026-11-20 verified (--picker-person-test): people listed and typed, OST Test 1 picked narrows My files (drops SharePoint App's Recordings), Clear restores; All files shows OST Test Team's logo in Location (getsitelogo). A person's-OneDrive picture wasn't seen live (no such folders reachable).

Built so far: the picker search's Person pill and menu; picking a person adds the modified-by/author clause (taken from OneDrive's code, since Teams' picker shows a stuck "Please sign in" on winpc); Location shows a site's logo or the owner's picture. Verified live: Person narrowed My files; All files showed the OST Test Team logo. Missing: the person-picture case seen live (needs a folder in someone else's OneDrive reachable to ost-test1); people are found via Graph /me/people, not OneDrive's own people search.

- 2026-11-20 (agent tuiF): Teams' picker All files on winpc still shows the stuck "Please sign in" (checked again), so Teams' Location pictures can't be measured live; the expected layout is taken from OneDrive's bundle code (spofilepickerwebpack, odsp-web-prod_2026-11-06.005): another site's logo (siteiconmanager/getsitelogo) or the OneDrive owner's picture, 16 px before the name. Test data: OST Test 3 created "OST TEST 128 shared folder" in its OneDrive and shared it with ost-test1 (edit, no mail) to check the person case in OST.

- 2026-11-20 AC2 (agent tuiF): OneDrive's picker code (spofilepickerwebpack 283) shows, before another site's Location, its SiteLogo, and for a person's OneDrive (SiteTemplateId 21 with AuthorOWSUSER) the hit's author picture (AuthorOWSUSER "account|name", a Large user coin), not the drive owner. OST now asks Graph search for AuthorOWSUSER and shows that person (resolved by account to their directory id; the drive owner only when the field is missing). Verified live (linuxlt, ost-test1, --picker-person-test --picker-person-all --picker-person-query="OST TEST 128"): "OST TEST 128 shared folder" in OST Test 3's OneDrive shows OST Test 3's picture before "OST Test 3's OneDrive"; the site-logo case was verified before. Teams' own picker still stops at "Please sign in" on winpc, so the layout comes from the bundle code. Test folder deleted.

- 2026-11-20 merged as 4f64ed1. Teams' own picker on winpc still stops at 'Please sign in', so AC2 follows OneDrive's picker code (author's picture before a person's OneDrive) and was verified in OST with a folder OST Test 3 shared.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Picker search as Teams: the Person filter narrows results (AC1), and Location shows the site's or person's picture before the name (AC2). For a person's OneDrive OST shows the hit author's picture, as OneDrive's picker code does (Graph has no owner for a partly shared OneDrive). Verified live with OST TEST 128 shared folder from OST Test 3 (deleted). Teams' own picker is stuck at Please sign in on winpc, so no live side-by-side of AC2.
<!-- SECTION:FINAL_SUMMARY:END -->
