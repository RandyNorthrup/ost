---
id: TASK-0299
title: 'Personal accounts: calls and meetings'
status: To Do
assignee:
  - '@tperC'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T08:06:00Z'
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
- [x] #5 Incoming calls ring for a personal account: the calling socket on go.trouter.teams.microsoft.com registered as SkypeSpacesWeb / TFLSkypeSpacesWeb_2.0 (TFL), as captured in docs/research/personal-accounts-protocol.md §9.3 (from TASK-0294)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams for personal use on the web (two personal test accounts): 1:1 call, ringing, meeting link, joining by link, meeting controls, New meeting form.
2. Calling for personal accounts: cpconv + X-Skypetoken instead of epconv + IC3, applicationType TFL, a second Trouter socket for calls registered as TFLSkypeSpacesWeb_2.0, wrapped call notifications, 1:1 calls in uni01 thread chats.
3. Meetings: teams.live.com/meet links joined by meetingData (shouldResurrect), Meet now through Teams free's middle tier.
4. Free-plan limits note, Record upsell, hide breakout rooms/Copilot/apps/Whiteboard/avatars/transcripts.
5. Live-check OST <-> Teams web between OST Personal 1 and 2.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Meet now from the calendar (--call-notes-test --call-notes-meetnow, live): made through Teams free's middle tier (teams.live.com/meet link), its chat named (from the create answer's groupContext), joined (connected). Meeting bar in a personal meeting: Chat, People, Raise, React, View, More, Camera, Mic, Share, Leave (no Controls, Rooms, Apps or Notes); 1:1 call bar: Hold, Chat, People, View, More, Camera, Mic, Share, Leave (dial pad now hidden; Record in More ▸ Record and transcribe, where Teams free has it on the bar).
- Not done / not verified: video calls; group calls from a chat (no personal-only group chat exists: there are two personal test accounts and their group chats include work users, where Teams turns calls off); calls with Teams desktop for personal use answering (testpc2's Teams desktop is signed in as Personal 2, but its windows are left alone; Teams on the web was the reference, and the "Teams on winpc" half of AC #1 can't apply: winpc is ost-test1, a work account, and Teams doesn't allow calls between personal and work accounts); a scheduled personal meeting joined from its calendar entry (same teams.live.com/meet path as the links); the free meeting's meeting options (Bypass lobby, Share screen) and the work options pane still shown in the form; the 60-minute end and any warning before it (not observed in Teams; OST shows the plan's limits on the form and offers the plans from Record, but doesn't end or warn); the Share tray's hidden Whiteboard row and the avatars (seen in code only).

Built so far (PR #84): AC #5 done (incoming calls ring and connect). AC #1: 1:1 audio calls both ways work with Teams on the web; video calls and group calls from a chat weren't run, and "with Teams on winpc" can't apply (winpc is a work account; Teams doesn't call between personal and work accounts). AC #2: Meet now, meeting links, the lobby and an anonymous guest work; the free plan's meeting options (Bypass lobby, Share screen) aren't built. AC #3: the form's 60-minute/100-participant note and Record's Microsoft 365 offer are built; the 60-minute end and warning aren't (Teams showed none in TASK-0287). AC #4: no Controls, Rooms, Apps (Whiteboard) or Notes on the bar (seen live); the Share tray's Whiteboard row and the avatars app are left out in code, not seen on screen.
- Incident: during the link hand-over check the calendar's join handler (not yet fixed) opened the teams.live.com link in linuxlt's Chrome; that page's pre-join took linuxlt's built-in microphone for under 2 s before the mic watcher moved it to ost_tperC_mic (23:00:57 local); the tab was closed within 3 minutes and never joined. The handler is fixed in this PR.
<!-- SECTION:NOTES:END -->
