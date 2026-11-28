---
id: TASK-0295
title: 'Personal accounts: People app, contacts, profiles and invites'
status: Done
assignee:
  - '@tperD'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T09:07:00Z'
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
- [x] #1 The People app shows the contacts with Chat, Call, Block, Delete and Invite as in Teams desktop
- [x] #2 Profile cards and pictures of personal-account people show as in Teams
- [x] #3 People search finds people by name, email or phone
- [x] #4 Invite to Teams links and the blocked list work as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams for personal use: People app on testpc2 (OST Personal 2 window, read-only) and teams.live.com as OST Personal 1 with a CDP capture: buddy list, block list, Delete, Block/Unblock, Invite to Teams, profile card.
2. Engine: api::tfl_people (buddy list, block list, delete, forget, add, invite link); profile card for 8:live: people from short profile + UPS presence.
3. UI: PersonalPeopleView (pane, All contacts / Active now, table with presence, Chat/Call/More (Block, Delete), Find, empty states, People settings and Blocked users with Unblock/Delete, Invite to Teams); ProfileCard Teams free mode (Overview/Contact/LinkedIn, More: Block contact).
4. Live: --tfl-people-test harness as OST Personal 1 on linuxlt (and block/unblock/delete/add back of OST Personal 2), chat list presence for TASK-0296.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (tperD) Research: Teams 26304 on testpc2 (OST Personal 2's window, UIA read-only, left minimized) and teams.live.com as OST Personal 1 (own headless Chrome on linuxlt, CDP capture with tokens redacted, worker bundle and en-us strings). Protocol in personal-accounts-protocol.md §10, UI in personal-accounts-features.md item 17.
- Found: contacts = MT buddy list (TflContacts group); Delete = block list add then managebuddies delete (also clears the block); Block/Unblock = blocklist/manage add/remove; blocked people leave the TflContacts group; Invite to Teams = join/template joinUrl (500 "Value cannot be null (locale)" without x-client-ui-language); Active now = on-network contacts not offline; no Add contact in Teams free (contacts come from chats and accepted requests).
- Built: api::tfl_people; personal People app (PersonalPeopleView: pane, All contacts / Active now with presence, Chat/Call/More (Block, Delete) and Teams free's dialogs, Find a contact, empty views, People settings with Blocked users (Unblock, Delete), Invite to Teams copying the link); Teams free profile card for 8:live: people (Overview/Contact/LinkedIn, shared email/phone or "contact details are hidden", More > Block/Unblock contact for a personal account); card Chat opens their thread or a new chat; call log stream (19:stream01_, streamofcalllogs) no longer listed as a chat.
- Live (linuxlt, OST Personal 1 in an isolated profile, harness --tfl-people-test --tfl-people-live="OST Personal 2"): All contacts and Active now list OST Personal 2 as Available; card shows Available and "OST Personal 2's contact details are hidden in Teams."; Invite to Teams copied the link (toast "Link copied to clipboard"); search found OST Test 3 by email (Federated) and Teams free people by name; Block moved Personal 2 to Blocked users (red badge), Unblock brought them back, Delete removed them, and they were put back as a contact (managebuddies add). Screenshots kept outside the repo.
- Not verified/not built: off-network (synced, not on Teams) contacts' row Invite button (no such contacts on the test accounts, their source call not captured); phone search (no test account has a number); Your profile's ··· (Edit name, Change profile picture) and Report a concern on the card (not built); Sync contacts Manage shows Teams' mobile-sync dialog rather than the Synced contacts page; Call from People uses OST's call path, which for personal accounts is TASK-0299. People is opened from View more apps until Teams free's rail (TASK-0297).

- Protocol notes: personal-accounts-protocol.md §11 (renumbered on rebase; §10 is the calls section).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A personal account's People app, profile cards, block list and invites now work as in Teams for personal use.

Changes:
- Engine (api::tfl_people): Teams free's buddy list (TflContacts), block list, Block/Unblock, Delete (block then managebuddies delete, as Teams free), Blocked users' Delete, add, and the Invite to Teams link (join/template with the UI language).
- People app for personal accounts (PersonalPeopleView): All contacts and Active now with presence, Chat, Call, More options (Block, Delete) with Teams free's dialogs, Find a contact, Teams free's empty views, People settings with Blocked users (Unblock, Delete), Invite to Teams.
- Profile card for 8:live: people (from personal or work accounts): Overview, Contact and LinkedIn, the shared email/phone or "<name>'s contact details are hidden in Teams.", presence from UPS, Block/Unblock contact for a personal account; Chat opens their thread or a new chat.
- The call log stream (19:stream01_…) is no longer listed as a chat.
- Research: protocol doc §11, features doc item 17.

Tests: tfl_people unit tests (buddy groups, profiles, block bodies, invite link), teams_free_call_logs_are_not_chats.
Live: OST Personal 1 on linuxlt with OST Personal 2 as the contact (list, Active now, card, invite link, search, block, unblock, delete, add back).
Not verified/built: off-network contacts' Invite row, phone search, Your profile's Edit name / Change picture, Report a concern.
<!-- SECTION:FINAL_SUMMARY:END -->
