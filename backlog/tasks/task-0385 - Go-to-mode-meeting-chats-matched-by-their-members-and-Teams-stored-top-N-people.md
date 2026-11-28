---
id: TASK-0385
title: >-
  Go-to mode: meeting chats matched by their members, and Teams' stored top-N
  people
status: To Do
assignee: []
created_date: '2026-11-28T08:00:00Z'
labels:
  - desktop
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0382. Teams' go-to (Ctrl+G) also matches meeting chats by their members (gotoEnableRosterMatchForNamedGroups: chatTitle.longTitle), so "test" lists OST AUDITB 1; OST reads members for group chats only, not the ~150 meeting chats. Teams' go-to people come from its stored top-N (substrate-suggestions-manager people store, ItemRank order), which on winpc differed from the peoplecache People row OST uses (OST Guest 02 second vs ost-personal2-0238). Teams also listed the empty, never-read unnamed chat "OST and OST Test 3" high with no horizon and no UKB score; find what ranks it there.

Built so far (TASK-0382): go-to ranking as Teams' WEIGHTED_AFFINITY/NORMALISED_ZSCORES (match bucket, recency from the consumption horizon, UKB affinity), the interleaved top people, named group chats' member line and member-name match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Meeting chats match their members' names in go-to as in Teams desktop
- [ ] #2 Go-to's people are Teams' stored top-N in its order
- [ ] #3 The unnamed empty chat's place in Teams' list is explained and matched, or documented why not
<!-- AC:END -->
