---
id: TASK-0169
title: Bot cards' plain Submit and messageBack buttons as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T20:44:00Z'
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

- 2026-11-20 (chatB): test flow "OST TEST 169 webhook card" (Workflows template "Send webhook alerts to a chat", OST group test, owner ost-test1) posts an Adaptive Card (Input.Text answer, a plain Action.Submit "OST TEST 169 plain submit" with data {choice: plain}, and an Action.Submit msteams messageBack "OST TEST 169 messageBack") sent by POSTing to its webhook. Teams on winpc: plain Submit shows the red "Unable to reach app. Please try again." bar (the Workflows bot does not take it); messageBack posts the displayText first (`content` "OST TEST 169 messageBack", messagetype Text, properties.skipfanouttobots true), then the card shows "Your response was sent to the app" and the bot answers in text ("Hi there! I'm here to keep you posted on workflow updates..."). Teams adds "OST Test 1 used a Workflow template to send this card. Get template" under the card. To delete afterwards: the flow, the card, the messageBack message and the bot reply.
<!-- SECTION:NOTES:END -->
