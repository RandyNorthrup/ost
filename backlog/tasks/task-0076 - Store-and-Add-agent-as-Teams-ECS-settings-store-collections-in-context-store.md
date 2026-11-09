---
id: TASK-0076
title: >-
  Store and Add agent as Teams: ECS settings, store collections, in-context
  store
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T13:23:00Z'
updated_date: '2026-11-09T13:33:00Z'
labels:
  - desktop
  - apps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' @ picker 'Add agent to the chat/channel' opens its in-context Store (bots only), and the Store itself is built from Teams' store content (CDN collections doc chosen by ECS), the app catalog, its ranking and the user's entitlements. OST's Store is an approximation with hard-coded lists. Rebuild both from Teams' own data, with Teams' live ECS settings as the source of flags.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST reads Teams' live ECS settings (the request Teams desktop makes, with the user's license details) and exposes them to features
- [ ] #2 The Store home shows Teams' collections, titles, order and apps from the store content doc and catalog, as Teams on winpc
- [ ] #3 @ picker 'Add agent to the chat/channel' opens the in-context store with installed bots, Teams' bot collections, search and See all, measured on winpc
- [ ] #4 Adding an agent installs it in the conversation as Teams does (verified with a Microsoft app in OST group test)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Authz: keep licenseDetails/region from Teams' authz in config.
2. api::ecs: Teams desktop's ECS request (MicrosoftTeams/49_1.0.0.0, agents TeamsNorthstar,TeamsBuilds,Segmentation,TeamsNorthstarUserOverrides, user/license filters), cached with ETag; setting(ns,key).
3. api::store_content: the collections doc (storecontent/apps[/smb]/{storeAppsCollectionsDoc}.json?ts=), parsed into collections.
4. Catalog + ranking + entitlements per collection (reuse app_details catalog/suggestions), resolve linkedEntities/itemsList as Teams' worker does.
5. In-context store dialog (BotGroupChat/BotTeam collection ids from ECS inContextStoreCollectionIdsOverwrite), measured layout; search; See all.
6. Capture Teams adding a Microsoft app (Polls) to OST group test; implement Add.
7. Store home from the same data.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- ECS: OST now makes Teams desktop's ECS request (captured at Teams start on winpc) with the authz licence details, caches it with its ETag, and serves settings (TeamsNorthstarUserOverrides over TeamsNorthstar). Verified on linuxlt: the same 430 KB reply, storeAppsCollectionsDoc = Enterprise/NewStoreCustomization/storev3.
- Store research written to docs/spec/store.md (content doc, ranked catalog API, in-context store collections, bot scope filter, layout).
<!-- SECTION:NOTES:END -->
