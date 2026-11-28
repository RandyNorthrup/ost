---
id: TASK-0294
title: 'Personal accounts: real-time updates'
status: In Progress
assignee:
  - '@tperA'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T04:25:00Z'
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
Messages, typing, read receipts and calls arrive for work accounts over Trouter. Personal accounts use the consumer Trouter and registrar (TFL registration); one source says chat messages don't arrive by push there and polls instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New messages, typing and read receipts appear within seconds for a personal account
- [x] #2 If push doesn't deliver chat messages, OST polls like Teams' web client does, without extra load when idle
- [ ] #3 Incoming calls and notification banners work for a personal account
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Personal accounts negotiate at the Skype Trouter (go.trouter.skype.com v4/a takes the consumer Skype token) and register at Teams free's registrar (edge.skype.com v2) with TeamsCDLWebWorker_2.7/TFL (ttl 3600) and <epid>_GG 2.3, re-registering before the ttl; no Better Together.
2. Chat pushes (NewMessage, typing, read receipts) flow through the existing data-frame parsing into event_hub, so the desktop reacts as for work accounts.
3. Calling registration (TFLSkypeSpacesWeb on the Teams Trouter) for incoming calls: check what is needed; calls are TASK-0299.
4. Live: OST Personal 1 in OST on linuxlt, messages/typing from OST Personal 2 via the chat service.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (tperA) Built: a personal account negotiates at the Skype Trouter (go.trouter.skype.com v4/a takes the consumer Skype token: pub-csm socket, edge.skype.com registrar) and registers its socket at Teams free's registrar https://edge.skype.com/registrar/prod/v2/registrations as the web client does (TeamsCDLWebWorker_2.7, productContext TFL, ttl 3600; <epid>_GG TeamsCDLWebWorker_2.3, ttl 86523; X-MS-Migration: True), re-registering before the ttl. No Better Together and no message_loss 1.9 re-registration for personal accounts. Web client's own handshake (check + /v4/c + user.authenticate) is in protocol doc §9.3.
- Live on linuxlt (OST Personal 1 in OST, profile tperAp1; OST Personal 2 sending through the chat service): both registrations succeeded, Trouter connected; Control/Typing and NewMessage pushes reached the socket within a second (OST_TROUTER_DUMP_DIR frames), and OST showed its notification banner for the message ("OST Personal 2: OST TASK-0294 banner check"; the chat's name is "Unknown" until TASK-0293 resolves personal chats' members). Chat messages do arrive by push, so no polling fallback is needed (AC #2).
- Not verified: read receipts. A consumption horizon PUT by OST Personal 2 gave no push, and the consumer chat service's /threads/{id}/consumptionhorizons answered an empty list; how Teams free shows Seen needs a capture with both accounts (TASK-0293's chat view).
- Not built: incoming calls. Teams free rings over a second socket on go.trouter.teams.microsoft.com registered as SkypeSpacesWeb / TFLSkypeSpacesWeb_2.0 at teams.microsoft.com/registrar/prod/v2 (captured, §9.3); answering needs the consumer calling stack (flightproxy cpconv), which is TASK-0299. Moved there as an AC.
<!-- SECTION:NOTES:END -->
