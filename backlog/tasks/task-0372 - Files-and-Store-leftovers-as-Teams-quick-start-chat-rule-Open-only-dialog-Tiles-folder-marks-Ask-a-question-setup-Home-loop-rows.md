---
id: TASK-0372
title: >-
  Files and Store leftovers as Teams: quick-start chat rule, Open-only dialog,
  Tiles folder marks, Ask a question setup, Home loop rows
status: In Progress
assignee:
  - '@t372'
created_date: '2026-11-27T21:01:00Z'
updated_date: '2026-11-28T02:56:00Z'
labels:
  - desktop
  - files
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0358 (PR #50). Left different or unverified: the Store quick-start dialog lists some chats Teams leaves out (Teams' rule unknown); the short Open-only quick-start dialog was never opened live; folder people/link marks are missing in Tiles view; OneDrive's knowledge-agent setup step for Copilot Ask a question is skipped; Teams' Home lists a loop_loopThread row OST leaves out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The quick-start dialog's chat list follows Teams' rule (researched and documented) and matches Teams for the same account
- [x] #2 The Open-only quick-start dialog (personal-scope-only app) is checked live against Teams
- [x] #3 Shared folders and shortcuts show Teams' marks in Tiles view too
- [ ] #4 Copilot Ask a question goes through OneDrive's knowledge-agent setup when Teams does
- [x] #5 Files Home lists Loop thread rows (loop_loopThread) as Teams does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research each leftover in Teams desktop (testpc1, ost-test1: UI Automation, read only) and in Teams' and OneDrive's own bundles (Teams package hashed-assets, OneDrive CDN bundles 2026-11-13.013).
2. AC1: port Teams' appInstallOptions chat rule (shared worker 40799/80647, dialog zd) to ContextlessDialog; compare with Teams' Power BI list.
3. AC2: open Avatars (personal only) in Teams and OST; match the short layout.
4. AC3: FolderCover signal and shortcut badge in Tiles.
5. AC4: trace OneDrive's knowledge agent flow for Ask a question; implement or document.
6. AC5: merge GetRecentFiles?top=40 into Home as OneDrive's RecentDataManager does.
7. Tests, build, live checks on linuxlt beside testpc1, PR with TASK-0359.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (2026-11-27): Teams package hashed-assets copied from testpc1 (26304.1207) and OneDrive CDN bundles odsp-web-prod_2026-11-13.013 (URLs from testpc1's WebView2 cache); Teams desktop on testpc1 (ost-test1) driven read-only with UI Automation (no CDP there); the knowledge agent flow from the winpc capture of 2026-11-26.
- AC1: the dialog's chats come from shared worker 40799 (enableAppDetailsConversationsManager on): conversations through 80647 Q9 and `we`, then the dialog's `zd` drops meeting chats. Against Teams' Power BI list (12 chats) OST had OST TEST 348 ×3 (chats you left), Just me (a `cfet` thread), Workflows (a bot 1:1 whose bot shows only as 28: sender/addedBy) too many and OST Personal 2 (Teams free 1:1, kept by Teams) missing. Fixed: unlisted, cfet (read where OST reads a thread), bot 1:1s left out; the 19:uni01_ exclusion dropped.
- AC2: Avatars (personal only) opens Teams' short dialog: 620 tall, "Let's go" 54 lower (286.8), Open at 388.3; OST matches; icon corners now take the band's shade.
- AC3: Tiles: People glyph and 20 px shortcut badge (FolderCover signal / shortcutTileOverlay), Shortcuts folder blue with its building, measured beside Teams' Tiles on testpc1.
- AC4: Teams sends updateKnowledgeAgentState only together with OneDrive's knowledge agent tools runtime (registerRemoteTools, execute_plan run in a sandbox against ~100 code-mode primitives). Not built here: TASK-0379 (follow-up).
- AC5: Home = GetRecentFiles?top=40 (prefer useSmartCache, filetypes) + DeltaSync, by Id (RecentDataManager). Live: OST's Home rows now equal Teams' on testpc1 (both loop_loopThread rows, both Highlights rows, in order, with Location and Owner).

- Live re-check with the final build (linuxlt, ost-test1, 2026-11-27): Power BI's quick start lists Teams' twelve chats in Teams' order plus "OST large chat test", which Teams leaves out for a reason not found (54 members of the tenant, last message 11-15, shown in Teams' chat list; likely Teams' local store). AC#1 stays open for it.
- AC#4 left open: TASK-0379 holds the knowledge agent tools runtime it needs.
- Tests: recent_files, drive::tests, chat::bot_chat_tests, app_places (19 passed, on linuxlt).
<!-- SECTION:NOTES:END -->
