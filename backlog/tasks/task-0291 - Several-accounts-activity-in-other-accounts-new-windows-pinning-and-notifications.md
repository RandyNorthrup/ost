---
id: TASK-0291
title: >-
  Several accounts: activity in other accounts, new windows, pinning and
  notifications
status: To Do
assignee: []
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T01:04:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0290
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With several accounts, Teams shows a badge and an 'Activity in your account and other orgs' list for the accounts in the background, opens their items in a new window, lets up to three accounts be pinned, and has a notification toggle per account in Settings > Accounts and orgs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Background accounts' unread activity shows as Teams' badge and list, and selecting an item opens it in that account's own window
- [x] #2 Accounts can be pinned and unpinned as in Teams (up to three)
- [ ] #3 Settings > Accounts and orgs has a notification toggle per account, and banners come only from accounts that have it on
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27 (t290, with TASK-0290) Built so far, checked against Teams 26304:
  - AC1: built by TASK-0244 (MtmaHub.qml: the app-bar tile with the other accounts' missed count, Teams' "Activity in other accounts and orgs" flyout v2, picking an entry opens it in that account's own window through its instance socket, or starts it). Verified then on linuxlt (spatest + test2).
  - AC2: built by TASK-0245 (Pin this org / Unpin this org, pinned org tiles above the hub tile, the org flyout). Teams 26304 allows two pinned orgs, not three: its hub sets pinningDisabled at two pinned tenants (measured on winpc 2026-11-22), and OST stops at two (MAX_PINNED_ORGS) with Teams' disabled item. The "up to three" in the AC comes from Microsoft's older docs. With a personal account (testpc2, TASK-0287) Teams' pin filled its icon but no pinned entry appeared and it was unpinned again on reopening.
  - AC3: Teams 26304 has no per-account notification toggle in Settings > Accounts and orgs: each account is a card (picture, name, address, Manage) with its org or "Personal" under it (winpc 2026-11-22 work + work; testpc2 2026-11-27 work + personal, ac2-set-04). OST's page is the same, so there is nothing to build until Teams ships the toggle.
  - Gap: a personal account's window has Teams for personal use's simpler hub (a 340-wide flyout: "Activity in other accounts and orgs", each other org with its count, Switch and a pin, then "Unread chat messages"); OST shows the work hub there. It belongs with the personal shell (TASK-0297).

- 2026-11-27 (t290) live on linuxlt with two work profiles (ost-test2, ost-test3; PR #69 build): the hub tile showed ost-test3's count, its flyout listed its activity and chats, and picking an entry made ost-test3's window open it ("another account's hub opened a chat here"). Pin this org added the org tile (S, count 3) above the hub tile and Unpin removed it (hub-pins.json empty again). AC1 and AC2 hold, with Teams' current limit of two pinned orgs. AC3 stays open: Teams 26304 has no such toggle (see the note above).

Built so far: the background accounts' badge and "Activity in other accounts and orgs" hub with items opening in that account's own window (TASK-0244, MtmaHub.qml) and Pin this org / Unpin this org with pinned org tiles (TASK-0245), both re-checked live 2026-11-27 (PR #69); Teams 26304 caps pinned orgs at two, as OST does. Left: AC3 has nothing to build while Teams 26304 shows no per-account notification toggle in Settings > Accounts and orgs; a personal account's window still shows the work hub instead of Teams for personal use's simpler one (TASK-0297).
<!-- SECTION:NOTES:END -->
