---
id: TASK-0380
title: >-
  Channels as Teams: Reminders rows for channel messages, the posts list's
  replies line, the post menu's missing items
status: To Do
assignee: []
created_date: '2026-11-28T02:55:00Z'
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
- [ ] #4 A channel meeting's post shows no calendar card with an empty date
<!-- AC:END -->
