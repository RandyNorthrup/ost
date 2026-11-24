---
id: TASK-0133
title: Profile card org chart and Show more sections, with real org data
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T03:26:00Z'
updated_date: '2026-11-21T02:31:00Z'
labels:
  - desktop
  - people
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' profile card Organization tab draws an org chart (managers above, peers and reports) when the directory has managers; the test tenant has none, so Teams shows 'We don't have the necessary details…' (which OST now matches, with Home / Back / Next). The hover card's 'Show more' sections also failed to load in Teams on 2026-11-12. Needs managers set for test users (Entra) to measure Teams' chart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With managers set for test users, the Organization tab draws Teams' org chart and its navigation (Home, Back, Next) walks it as in Teams
- [x] #2 The sections under Show more match Teams'
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 tenant (user: "you are authorized to adjust anything in the test tenant to unblock us"): OST Test 2 set as OST Test 1's manager (Microsoft 365 admin center), so profile cards have an org chart to show.

- 2026-11-15 23:40: Graph has the manager (ost-test1 → OST Test 2), but Teams on winpc still shows "We don't have the necessary details…" for both people. Teams' live persona card reads org data from Loki (nam.loki.delve.office.com api/v1/organization and the GraphQL useOrgExplorerQueryRef_OrganizationQuery), which syncs from the directory with a delay. Re-check after 2026-11-16. OST reads Graph, so it can show a manager while Teams can't; to match, OST should use Teams' Loki calls (needs a Loki token).

Built so far: The profile card's Organization tab (manager and reports from Graph) with Home/Back/Next, and Show more opening the full card. Missing: Teams' drawn org chart from Loki, and a side-by-side check. (Audit 2026-11-16)

- 2026-11-20 winpc: Loki now has the manager (set 2026-11-15): Teams' card shows OST Test 2 with "People reporting to OST Test 2 (1)" and the Organization tab draws the chart. Captured the request (CDP, token not kept): POST https://nam.loki.delve.office.com/api/v2/graphql?operationName=useOrgExplorerQueryRef_OrganizationQuery (Loki token aud 394866fc…, Teams' lokiTokenResourceUrl https://loki.delve.office.com/; x-clientfeature LivePersonaCard, x-clientscenario GetOrgExplorerV2), variables {personIds {aadObjectId, smtp}, directsToLoad 20, worksWithToLoad 25…}; multipart @defer answer: personInFocusV2 with managerChainTopToBottom, directs, workingWith, presence. Layout measured (OST Test 2): nav bar 40 (#FAFAFA), focus card 495.4 x 156.7 at 127.6 (64 px picture, name 16/22 semibold, #F0F0F0 line at 100, View profile 127 x 31.3, "1 report / 1 direct" 10/14 semibold), "People reporting to **name**" between rules 16 under, report cards 369.3 x 85.3 in two columns (48 px picture, name 14 semibold, job title, location), "**name** also works with (i)" with 128.6 x 140 tiles.
- Built: api::profile::org_chart (Loki query cut to the drawn fields, multipart merge, org_from + unit test), loaded with the card; ProfileCard Organization draws Teams' chart (manager chain linked above the focus card, reports grid, works-with tiles, View profile → Overview, a card makes that person the focus; Home/Back/Next walk them); the old Graph view stays when Loki can't answer. Harness --profile-org-test.
- Live (linuxlt, ost-test1): OST Test 1 → managers [OST Test 2], works with [OST Test 3, Randy Northrup]; visiting OST Test 2 → "1 report / 1 direct", reports [OST Test 1], works with [Randy Northrup]; Back returns to OST Test 1 — the same people Teams shows.

- 2026-11-20 layout to Teams' measures (docs/spec/profile-card.md 'Organization tab'): manager cards 84 tall with 48 px pictures and the reports count, the focus card 156.7 with View profile and '1 report / 1 direct', 'People reporting to {name}' rules, report cards, '{name} also works with' / 'You work with' tiles. Live again with the final build (--profile-org-test, ost-test1): same people and navigation as Teams. Open: AC2 (the hover card's Show more sections) and the AC3 side-by-side still need winpc, which other agents held.

- 2026-11-20 merged: org chart from Loki to Teams' measurements with Home/Back/Next, verified live. AC2/AC3 open (need winpc).

- 2026-11-20 AC2 (winpc, OST Test 2's hover card from a message picture): the hover card's Show more opens the full card on Profile (Contact information); the sections under it are 'Direct reports (n) ›' (12/16 bold, 18 px chevron) at 24, 392, the reports' 40 px pictures (AvatarGroup, each opens that person) from 24, 422, and 'Show organization' (12 px brand link, 131 x 32) at 8, 466; the heading and the link open Organization. Built in HoverCard.qml from the card's Loki org data (Graph reports as fallback); spec in docs/spec/profile-card.md. Live (linuxlt default, --hovercard-test after the card's data loads): OST Test 2's card shows Profile ›, the email, Show more, Direct reports (1) › with OST Test 1's picture and Show organization below (the card scrolls at 446), the same as Teams' picture; Show more opened the full card on Profile.
- AC3: side by side on 2026-11-20: Teams' hover card (winpc capture) and OST's (--hovercard-test) list the same sections and people; the Organization tab was compared earlier the same day (same managers, reports and works-with). Not covered: the 'Reports to' block Teams may show for someone with a manager (only ost-test1 has one, and you can't hover your own card).

- 2026-11-20 merged as 0509286; 844 lib + 29 desktop tests pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Profile card org chart and Show more as Teams.

- Org data comes from Loki (Teams' people-relationship service), not Graph; the Organization tab draws Teams' chart (managers, the person with reports count, reports, works-with) and Home / Back / Next walk it.
- The hover card's Show more opens the full card on Profile; Direct reports (n) with pictures and Show organization link to Organization, a picture opens that person's card.

Verified side by side with Teams on winpc using OST Test 2's card (Direct reports (1): OST Test 1). Not covered: a Reports to block for someone with a manager (only ost-test1 has one, and you can't hover your own card).
<!-- SECTION:FINAL_SUMMARY:END -->
