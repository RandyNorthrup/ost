---
id: TASK-0090
title: >-
  Act on synced chat settings as Teams: compact density, chat landing,
  auto-follow, suggested replies
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-10T10:14:00Z'
updated_date: '2026-11-10T12:08:00Z'
labels:
  - desktop
  - settings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings ▸ Chats and channels now saves these where Teams does (TASK-0088), but OST doesn't yet behave by them: Compact message density (Teams' compact message layout), When I open a chat take me to Last read / Newest message (with the new-messages divider), automatically following channel threads you start, reply to or are @mentioned in, and suggested replies in chat.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Compact density lays out messages as Teams' compact mode
- [x] #2 Opening a chat lands on the last read message or the newest, as chosen, with Teams' new messages divider
- [x] #3 Threads you start, reply to or are @mentioned in are followed as the auto-follow choices say
- [ ] #4 Suggested replies show in chats as Teams' when on
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Chat landing done: opens on the Last read line (or newest, per setting); read position honours consumptionHorizonBookmark (Mark as unread), checked against Teams' Last read line on the Randy 1:1.

- Compact density done (measured on winpc in compact, compared side by side).

- Auto-follow is the service's: posting OST TEST 80 in OST Test Team ▸ General from Teams sent only the message POST, no follow request; the choices are the synced userPersonalSettings.teamsAndChannelsSettings.autoFollow* (saved by Settings ▸ Chats). OST posts the same way, so OST behaves as Teams.
- Left: suggested replies (needs Teams' smart-reply service research).
<!-- SECTION:NOTES:END -->
