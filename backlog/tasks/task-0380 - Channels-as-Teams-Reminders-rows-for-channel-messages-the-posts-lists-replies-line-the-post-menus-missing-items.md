---
id: TASK-0380
title: >-
  Channels as Teams: Reminders rows for channel messages, the posts list's
  replies line, the post menu's missing items
status: In Progress
assignee:
  - '@t380'
created_date: '2026-11-28T02:55:00Z'
updated_date: '2026-11-28T06:16:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Differences seen beside Teams desktop 26304 (testpc2 as OST Test 2, testpc1 as ost-test1) during TASK-0373, 2026-11-27; not covered by an existing task (searched the backlog and the QML):
- Chat > Reminders: Teams shows a channel message's reminder like a Followed threads row (the channel's picture and name, the post's subject, then "{sender}: {text}" after the sender's 20 px picture) and an upcoming reminder's chip with a grey outline; a chat reminder's text wraps to two lines. OST shows every row as a chat row, one line, brand chip.
- Posts list: Teams' replies line reads "Open {n} replies from {people}"; OST shows "{n} earlier reply".
- Channel post and reply ··· menus: Share to Outlook, Immersive Reader and Report this message are missing (MessageHost: "not built yet").
- A channel meeting's post in OST shows a calendar card dated "Sunday, December 31, -0001" (an empty start) that Teams doesn't show.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A channel message's row in Chat > Reminders looks as in Teams (channel, post subject, sender line, chip styles; two-line text for chats), checked side by side
- [ ] #2 The posts list's replies line reads as Teams' does
- [ ] #3 Channel post and reply menus include Share to Outlook, Immersive Reader and Report this message where Teams shows them
- [x] #4 A channel meeting's post shows no calendar card with an empty date
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams 26304 (bundles + Teams web as OST Test 2): reminders slice rows, response summary, channel menu registry.
2. Reminders: parse parentMessageSubject/Preview for channel replies; channel rows as Followed threads rows; chip styles per state; two-line chat text.
3. Posts list: Teams' response summary text (response_summary_N_users_mf), 12/16 brand, opens the post view.
4. Channel post/reply menus: secondary items in registry order (first 3 on the menu, rest under More actions), Report this message for others' messages; Share to Outlook on the channel id (bodyType SingleMessage in Threads channels).
5. Harness --channel-rows-test; unit test; live check beside Teams.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: AC #4 is met by TASK-0378 (PR #72, merged 2026-11-27): ended channel-meeting posts with the .NET zero date no longer get a calendar card (src/api/messages.rs, Teams' after-1970 rule, unit test). TASK-0373's agent saw the '-0001' card on a build from before that merge.
<!-- SECTION:NOTES:END -->
