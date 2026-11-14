---
id: TASK-0132
title: >-
  Bot card actions as Teams: Action.Submit / Execute invokes, result footer,
  Polls
status: To Do
assignee: []
created_date: '2026-11-14T01:37:00Z'
labels:
  - desktop
  - messages
  - cards
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cards from bots and apps carry actions that call the bot: Action.Submit and Action.Execute (Universal Actions) send an invoke and Teams replaces or updates the card, with a result footer; the Polls app's poll card votes this way. OST renders these cards but their bot actions do nothing yet. Polls is installed in OST group test (AddCustomApp rows) for testing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Action.Submit and Action.Execute on a bot's card send Teams' invoke and the card updates as in Teams (refresh, result footer, errors)
- [ ] #2 A poll from the Polls app shows and can be voted on from OST, and the results show as in Teams
- [ ] #3 Verified side by side with Teams on winpc
<!-- AC:END -->
