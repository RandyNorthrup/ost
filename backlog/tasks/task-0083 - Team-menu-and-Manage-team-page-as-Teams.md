---
id: TASK-0083
title: Team menu and Manage team page as Teams
status: To Do
assignee: []
created_date: '2026-11-09T20:42:00Z'
updated_date: '2026-11-09T20:42:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams has a ··· menu on each team row (Hide all channels, Add member, Add channel, Manage team, Get link to team, Manage tags, Leave/Edit/Delete team…; docs/spec/chat-list-and-header.md §5.6) and a Manage team page (Channels, Members, Pending requests, Settings, Analytics, Apps, Tags). OST's team rows have no menu and there is no Manage team page; Manage channel's All Channels and Analytics across channels lead there in Teams.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each team row has Teams' ··· menu with Teams' items, conditions and order
- [ ] #2 Manage team opens Teams' page in the conversation's place with its tabs, each measured against Teams
- [ ] #3 Manage team ▸ Analytics shows the team's analytics (Summary with Active guests, Engagement, charts; Analytics across teams) and Manage channel's All Channels / Analytics across channels open it
- [ ] #4 Verified side by side with Teams on winpc in OST Test Team
- [ ] #5 Manage channel ▸ Settings for a channel other than General shows Teams' channel moderation and settings (verified with a test channel made by Add channel in OST Test Team)
<!-- AC:END -->
