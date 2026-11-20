---
id: TASK-0169
title: Bot cards' plain Submit and messageBack buttons as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T18:22:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST sends invoke-style Action.Submit, imBack and polls, but not plain Action.Submit or messageBack buttons (TASK-0132).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Plain Action.Submit and messageBack buttons send what Teams sends, and the bot answers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: plain Action.Submit (no msteams) and messageBack as Teams' code does them: the display text posted first (skipfanouttobots), then the messageback invoke with the text and the card's inputs; hero-card messageBack buttons with the response bar (da0a317).

Not yet verified: no installed bot sends these buttons (Workflows replies in plain text; Polly installed for ost-test1 sent no card). Needs a bot that sends a plain Submit/messageBack card to capture Teams' request and check the answer.

- 2026-11-20 (chat agent): still open. ost-test1's installed apps with bots are Polly, Workflows, Polls, Clipchamp, Power BI, Praise, Updates and Viva Learning (from Teams' "+" on winpc); none sends a card with a plain Action.Submit (no msteams) or a messageBack button in this tenant's chats (Polls uses invoke-style Submit, Workflows answers in text, Power BI's bot answers 1008 Unauthorized). Verifying needs a bot that sends such a card (e.g. a Workflows "post card and wait for a response" flow, or a registered test bot), which needs the user's go-ahead to create.
<!-- SECTION:NOTES:END -->
