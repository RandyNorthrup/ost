---
id: TASK-0168
title: App link cards for links to apps' sites, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T11:49:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For links to sites that have a Teams app (GitHub, Wikipedia…), Teams shows that app's card instead of the plain preview. OST shows the plain preview only (TASK-0148 built plain previews).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sites without an app keep the plain preview
- [x] #2 A link to a site whose Teams app allows anonymous use shows that app's card in compose and in the sent message, as Teams on winpc does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (da0a317); spec docs/spec/url-previews.md.
- Verified: OST showed Teams' OST TEST 168a card; OST's OST TEST 168c went out with the Wikipedia Search card and Teams on winpc showed it; www.github.com and rust-lang keep the plain preview; Collapse preview sends a plain preview (168b). Re-checked on the merged build.
- Installed apps (queryLink) and sign-in cards: TASK-0200.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Links to sites with a Teams app show that app's card, as Teams.

- src/api/link_unfurl.rs: Teams' domain matching over the app catalog (installed apps first, anonymous apps otherwise; cached in ~/.cache/ost/link-apps.json), composeExtension/anonymousQueryLink (queryLink when installed), and the send format (inline-compose-card span, properties.cards, preview off).
- AppLinkCard.qml in compose and messages; Collapse/Expand preview as Teams.
- Fixed: a message with a card and long text no longer exceeds the bubble width.

Tests: unit tests for matching and the send body; live both ways with winpc Teams. Follow-up: TASK-0200.
<!-- SECTION:FINAL_SUMMARY:END -->
