---
id: TASK-0076
title: >-
  Store and Add agent as Teams: ECS settings, store collections, in-context
  store
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T13:23:00Z'
updated_date: '2026-11-09T15:00:00Z'
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
- [x] #2 The Store home shows Teams' collections, titles, order and apps from the store content doc and catalog, as Teams on winpc
- [x] #3 @ picker 'Add agent to the chat/channel' opens the in-context store with installed bots, Teams' bot collections, search and See all, measured on winpc
- [x] #4 Adding an agent installs it in the conversation as Teams does (verified with a Microsoft app in OST group test)
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

- In-context Store done: the @ picker offers "Add agent to the chat/channel" (Teams' order, rows 5 apart). It opens Teams' in-context Store from the store content doc, the ranked catalog (beta/users/apps/store), Teams' collection rank, featured apps first, and Teams' thresholds (6 apps, 1 agent). Only bots in the conversation's scope are offered, already-added ones are excluded, and the bots already added are shown as tiles. See all, and server search ("Search results for")., Verified side by side with Teams on winpc in OST group test and OST Test Team General: same installed bots and the same collections. Item order follows Teams' personalised rank service, and the CDN served linuxlt a newer doc.
- Add: clicking an app opens its details with Back to the Store. Add installs it as Teams does (POST users/apps/entitlements, then chats/{id}/apps/entitlements, captured on winpc). Verified live: OST added Polls to OST group test; Teams shows "OST Test 1 added Polls here."; OST shows "About this bot" as Teams does.
- Chat events: AddCustomApp/DeleteCustomApp now read as Teams words them (apps icon, bold app name), and bots' member events are hidden.
- Not verified live: adding an agent to a channel (team endpoint plus X-Ms-Appinstall-Channelid, from Teams' code), and the @mention after adding a conversational bot. The details' generic Add (from the Store) now does the personal install instead of opening Teams on the web.
- Left: AC2, the Store home from the same data.

- Store home rebuilt (AC2) from Teams' data: the feed collections in feedOrder (with Teams' cards, the installed check, and disableRatings), the Featured and Categories menus (nav sections, Teams' icon map), See all and category pages, and search. Checked against Teams on winpc: the same feed titles and order, and the same menus.
- Root cause of the earlier CDN differences: without authz licenseDetails, OST asked for the Enterprise store doc instead of apps/smb. ecs::license now fetches them when missing, so ECS and the Store use the same filters as Teams.
- Also found: the build script copied a stale binary after a failed build; it now fails.
- Follow-up TASK-0077: the Devices tab, See all filter and Manage your apps.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's Store and the @ picker's "Add agent" now work as Teams' do, built from Teams' own data.

Changes:
- `api::ecs`: Teams desktop's live settings request (captured at Teams start), with authz licence details (now kept in the config, fetched when missing), cached with its ETag. Settings are read as Teams reads them.
- `api::store_content`:
  - the store content doc (CDN), merged with Teams' burnt-in collections (`store_defaults.json`), the ranked catalog (`beta/users/apps/store`), the collection rank service, featured apps, chat and team apps, and server search;
  - Add/remove via the entitlements endpoints Teams uses.
- `AgentStore.qml`: Teams' in-context Store (installed bots, collections, See all, search). App details open from it with Back; Add installs into the conversation; "About this bot" for bots that only notify.
- `StoreView.qml`: Teams' Store home (banner, feed, Featured/Categories menus, See all, category pages, search, installed checks).
- Chat events: "added {app} here." and "removed {app} from the chat." as Teams words them; bots' member events hidden.

Verified on winpc against Teams in OST group test and OST Test Team General: the same collections and menus. OST added Polls and Teams showed it.

Tests: `cargo test --lib` (362 pass), including new ECS, store, event and menu tests.

Follow-ups:
- TASK-0077: the Devices tab, See all filter and Manage your apps.
- Adding an agent in a channel is implemented from Teams' code but not checked live.
<!-- SECTION:FINAL_SUMMARY:END -->
