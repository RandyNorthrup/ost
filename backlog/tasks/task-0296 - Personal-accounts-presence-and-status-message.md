---
id: TASK-0296
title: 'Personal accounts: presence and status message'
status: Done
assignee:
  - '@tperD'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T08:49:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0294
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal accounts get presence from the consumer presence service, not Graph or the work presence service.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Your own availability and status message can be set and are shown to others, as in Teams
- [x] #2 Contacts' presence shows in the chat list, chats, profile cards and People
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (Built: own presence, AC #1.)
2. Contacts' presence: chat list 1:1 peers (peer MRIs from the thread members since PR #81), the chat header, Teams free profile cards (short profile + UPS) and the People app (UPS for the buddy list).
3. Live as OST Personal 1 with OST Personal 2's presence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (tperA) Built: presence requests of a personal account go to Teams free's unified presence (regionGtms presenceUPS, only a teams.live.com https host, else https://teams.live.com/ups/global) with the middle tier bearer + x-skypetoken + x-ms-client-consumer-type: teams4life (without it UPS answers 400 "Consumer client type header must not be empty"); same paths as work: me/endpoints, forceavailability, publishnote, getpresence; no reportmyactivity (Teams free reports activity on the socket). The status message is plain text, at most 280 characters, without "Show when people message me" (hidden for personal accounts in the status editor), expiry as Teams (Never = 9999-12-31 local). Web client's calls captured in protocol doc §9.4.
- Live on linuxlt (OST as OST Personal 1, read back as OST Personal 2 through UPS getpresence): the presence endpoint was published (deviceType Desktop), Busy set from OST's status menu showed as Busy/Busy to Personal 2, and the status message typed in OST's editor ("ost task-0296 status check", Never) showed as the note with expiry 9999-12-31T08:00:00Z. OST's own chat-list badge showed Busy.
- AC #2 not done: OST asks UPS for contacts' presence by the chat list's peer MRIs (and profile cards/People by theirs), and getpresence answers for 8:live: MRIs in OST's request shape (checked: Personal 2 set to Do not disturb -> DoNotDisturb). But a personal account's chats don't carry their peer yet (the 1:1 shows "Unknown" with no peer MRI: TASK-0293), and personal People/profile cards are TASK-0295, so no contact's presence is on screen yet.

Built so far: presence for personal accounts goes through Teams free's UPS (teams.live.com/ups/global, consumer headers); own availability and status message (plain text, 280 chars, no pinned option) set from OST and verified live as seen by another personal account (AC #1). Left: contacts' presence on screen waits on TASK-0293 (personal chats' peer names/MRIs) and TASK-0295 (People and profile cards); UPS already answers for 8:live: MRIs in OST's request shape.

- 2026-11-28 (tperD, with TASK-0295) AC #2: since PR #81 a personal 1:1 thread carries its peer (thread members), so the chat list's presence poll covers Teams free contacts; the People app reads its contacts' presence from UPS; Teams free profile cards read it from UPS too. Live (linuxlt, OST Personal 1): the chat list and the chat header show OST Personal 2 as Available (green badge), the People app lists them as Available (and under Active now), and their card says Available.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Presence for personal accounts is complete: own availability and status message (PR #82) and now contacts' presence in the chat list, chat header, Teams free profile cards and the People app, all from Teams free's UPS. Verified live as OST Personal 1 seeing OST Personal 2 Available everywhere.
<!-- SECTION:FINAL_SUMMARY:END -->
