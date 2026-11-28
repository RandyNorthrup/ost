---
id: TASK-0383
title: 'Channel posts: bold replies line for unread replies, as Teams'
status: To Do
assignee: []
created_date: '2026-11-28T07:19:00Z'
labels:
  - desktop
  - channels
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0380 (PR #83). Teams draws a post's 'Open N replies from …' line in bold when the post has replies you haven't read; OST doesn't track unread replies per post there. Also not tried live: Share to Outlook in a Threads-layout channel (a different draft type).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A post's replies line is bold exactly when Teams shows it bold (unread replies), and returns to normal once they're read
- [ ] #2 Share to Outlook from a Threads-layout channel creates the same draft Teams creates (checked live, draft deleted after)
<!-- AC:END -->
