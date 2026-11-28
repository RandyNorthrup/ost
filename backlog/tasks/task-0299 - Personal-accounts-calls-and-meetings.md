---
id: TASK-0299
title: 'Personal accounts: calls and meetings'
status: In Progress
assignee:
  - '@tperC'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T06:21:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0294
  - TASK-0298
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal-account calls go through the consumer conversation service with the Skype token and may need browser-style media (DTLS-SRTP, BUNDLE) instead of the format OST uses for work calls. Free meetings are limited to 60 minutes and 100 people (Microsoft 365 Personal or Family raise this); recording needs a subscription and is kept 30 days in the meeting chat.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 1:1 audio and video calls and group calls from a chat work between personal test accounts and with Teams on winpc
- [ ] #2 Meet now and scheduled personal meetings work, including joining as a guest, with Teams' meeting roles and options
- [ ] #3 The meeting limits, warnings and upgrade prompts match Teams for a free account
- [ ] #4 Features Teams doesn't offer personal accounts (breakout rooms, Whiteboard, avatars) are not shown
- [ ] #5 Incoming calls ring for a personal account: the calling socket on go.trouter.teams.microsoft.com registered as SkypeSpacesWeb / TFLSkypeSpacesWeb_2.0 (TFL), as captured in docs/research/personal-accounts-protocol.md §9.3 (from TASK-0294)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams for personal use on the web (two personal test accounts): 1:1 call, ringing, meeting link, joining by link, meeting controls, New meeting form.
2. Calling for personal accounts: cpconv + X-Skypetoken instead of epconv + IC3, applicationType TFL, a second Trouter socket for calls registered as TFLSkypeSpacesWeb_2.0, wrapped call notifications, 1:1 calls in uni01 thread chats.
3. Meetings: teams.live.com/meet links joined by meetingData (shouldResurrect), Meet now through Teams free's middle tier.
4. Free-plan limits note, Record upsell, hide breakout rooms/Copilot/apps/Whiteboard/avatars/transcripts.
5. Live-check OST <-> Teams web between OST Personal 1 and 2.
<!-- SECTION:PLAN:END -->
