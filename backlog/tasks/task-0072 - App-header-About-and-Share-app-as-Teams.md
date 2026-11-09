---
id: TASK-0072
title: App header About and Share app as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T07:57:00Z'
updated_date: '2026-11-09T11:52:00Z'
labels:
  - desktop
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A personal app's header menu in Teams (Help window, measured on winpc 2026-11-09: More <app> actions) offers Reload app, About and Share app. About opens Teams' app details dialog (app-details-northstar-dialog, 898.7 x 563.67: the app's tile and name, developer, rating and review counts, installs in the last month, Works in, pricing, then its description and details). Share app opens Teams' Share form (Share to picker, 'Say something about this' with 'Take a look at this app.' and the app's card, Share). OST's app header offers Reload app only until these exist.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 About opens Teams' app details dialog for the app, with the same sections and data as Teams (measured on winpc)
- [x] #2 Share app opens Teams' Share form; sharing posts the app card as Teams does (tested only into OST group test or OST Test Team)
- [x] #3 Both appear in the app header menu in Teams' order (Reload app, divider, About, Share app)
- [x] #4 A shared app card renders in chat as Teams renders it (Privacy, Terms of use, Permissions; Open, View details, share), and View details opens the app's About
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research (done): winpc dumps of the About dialog, the Share form and the shared card; the bundles' data sources (scratchpad ab/spec-agent.md); a read-only probe of every endpoint (ab/probe.txt). Desktop reads ratings from AppSuggestions api/v2/apps/ratings (middle-tier rating returns 500).
2. Capture the sub-views live: detailed permissions, See all reviews, the Write a review form (never submitted), languages expanded, More like this navigation.
3. Library api::app_details: definition (batchedDefinitions), rating, installs, reviews (count, pages, sort and filter), More like this (definitionsv2 catalog + suggestions rank), permissions from the manifest, languages to native names, works-in and pricing, the share message and its card. Unit tests on the derivations.
4. QML AppDetailsDialog with its views and history; About in the app header menu.
5. ShareForm (Share to picker, compose, card preview, Copy link, Share, "shared" confirmation) and Share app in the menu; post as Teams.
6. Chat: shared app cards with Teams' footer and buttons; View details opens About.
7. Verify against winpc (side by side), share only into OST group test, docs, commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Data: middle tier batchedDefinitions; AppSuggestions api/v2/apps/ratings (the desktop worker's source; the middle tier's per-app rating answers 500), odata usage and reviews; definitionsv2 + suggestions ranking + the user's aggregated entitlements for More like this (reproduces Teams' six for Help exactly).
- Ported Teams' permission keys and categories, capability rows, languages (locale table), pricing and Works in; Teams' strings come from its en-us locale.
- Squircle tiles (CSS corner-shape superellipse(2)); Adaptive Card Icon element from Teams' Fluent icon CDN; roundedCorners images; ExtraSmall spacing.
- Verified on linuxlt against winpc: dialog and every view (Write a review and Report review opened, never submitted), the Help window's menu, the Store, the shared card in OST group test (Teams' own and OST's), and a share from OST into OST group test (stored like Teams' post).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' app details dialog (About) and Share app, plus shared app cards in chats.

Changes:
- `api::app_details` gathers an app's details as Teams does:
  - the definition, the AppSuggestions rating and histogram, installs in the last month, reviews (sort, paging), and More like this (catalog + suggestions ranking + your entitlements);
  - permissions (Teams' key derivation and categories), capabilities, languages, pricing and Works in;
  - the share message and its Adaptive Card; posting and reporting reviews.
- `AppDetailsDialog.qml` lays out every view as measured on winpc:
  - the page, with a sticky header and scroll progress;
  - All reviews (Sort, Report review), Permissions, and Write a review;
  - Back through More like this.
- `ShareForm.qml`:
  - Teams' Share form, with People/Chats/Channels suggestions, the message and the card preview;
  - Copy link, Share, then "Your message has been shared." with View and Done.
- App header menu: Reload app, a divider, About, Share app. The Store and teams.microsoft.com/l/app links now open the dialog.
- In chats, shared app cards show Teams' footer (`AppCardFooter.qml`): Privacy, Terms of use, Permissions, Open, View details, share.
- `AdaptiveCard.qml` gains the `Icon` element (Teams' Fluent icon CDN), `roundedCorners` images, `ExtraSmall` spacing, a card-level `selectAction`, and an optional footer.
- Spec: docs/spec/app-details.md.

Tests:
- `cargo test --lib app_details` (6 tests).
- Live on linuxlt against winpc Teams:
  - every view; Write a review and Report review were opened but never submitted;
  - the Help window's menu and the Store;
  - a share into OST group test, read back from the chat service and matching Teams' post.
<!-- SECTION:FINAL_SUMMARY:END -->
