---
id: TASK-0295
title: 'Personal accounts: People app, contacts, profiles and invites'
status: In Progress
assignee:
  - '@tperD'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T07:52:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0293
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams for personal use has a People app in the left rail: contacts (synced from Outlook.com and the old Skype list), Active now, blocked people, invite links and invites by email or phone, profile cards and people search through the consumer middle tier.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The People app shows the contacts with Chat, Call, Block, Delete and Invite as in Teams desktop
- [ ] #2 Profile cards and pictures of personal-account people show as in Teams
- [ ] #3 People search finds people by name, email or phone
- [ ] #4 Invite to Teams links and the blocked list work as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams for personal use: People app on testpc2 (OST Personal 2 window, read-only) and teams.live.com as OST Personal 1 with a CDP capture: buddy list, block list, Delete, Block/Unblock, Invite to Teams, profile card.
2. Engine: api::tfl_people (buddy list, block list, delete, forget, add, invite link); profile card for 8:live: people from short profile + UPS presence.
3. UI: PersonalPeopleView (pane, All contacts / Active now, table with presence, Chat/Call/More (Block, Delete), Find, empty states, People settings and Blocked users with Unblock/Delete, Invite to Teams); ProfileCard Teams free mode (Overview/Contact/LinkedIn, More: Block contact).
4. Live: --tfl-people-test harness as OST Personal 1 on linuxlt (and block/unblock/delete/add back of OST Personal 2), chat list presence for TASK-0296.
<!-- SECTION:PLAN:END -->
