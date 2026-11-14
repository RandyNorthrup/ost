---
id: TASK-0132
title: >-
  Bot card actions as Teams: Action.Submit / Execute invokes, result footer,
  Polls
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T01:37:00Z'
updated_date: '2026-11-14T02:43:00Z'
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
- [x] #1 Action.Submit and Action.Execute on a bot's card send Teams' invoke and the card updates as in Teams (refresh, result footer, errors)
- [x] #2 A poll from the Polls app shows and can be voted on from OST, and the results show as in Teams
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-13: Captured Teams' invoke (POST {chatsvc}/v1/agents/{bot}/invoke; body name/appId/messageType/value/imdisplayname/userAadToken/serverMessageId/clientMessageId/conversation; X-MS-AutoRefreshRequestInThread on automatic refresh). Built src/api/bot_invoke.rs (+tests) and examples/bot_invoke.rs; OST's author refresh (fetchAuthorVoteCard) on OST TEST 126 returned the author card. Next: wire refresh + Submit/Execute into AdaptiveCard/Conversation, the "Your response was sent to the app" footer, Edited/Updated labels, "via Polls" sender.

- Wired: Backend.card_invoke (appId from the catalog), Conversation.cardAction / maybeRefreshCard / cardOverrides ("Updated"), CardResponseBar.qml, "{name} via {bot}" sender (MessageView.on_behalf_of), bot avatars from their app icon (photo_for 28: → app_details::app_for_bot), bare bot cards, grouped "Edited" line. Harness --poll-test [--poll-vote=N].
- Live: OST Test 1 voted Red from OST; Teams on winpc shows Red 100% (1). OST Test 2 isn't in OST group test.
- Not done: plain Action.Submit / messageBack (logged, not sent).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bot cards' actions now work as in Teams, with a poll from the Polls app as the test.

Changes:
- src/api/bot_invoke.rs: Teams' invoke (POST {chatsvc}/v1/agents/{bot}/invoke; body and automatic-refresh header as captured), values for invoke Action.Submit and Action.Execute/refresh, and reply reading (card / message / error / sent). Tests.
- Backend.card_invoke fills the bot's appId from the app catalog (app_details::app_for_bot).
- Conversation: card actions, one refresh a session for the users the card names, refreshed cards replace the original ("Updated" in the meta line), Teams' response bar (CardResponseBar.qml) with "Your response was sent to the app", messages or errors.
- Messages: "{name} via {bot}" sender lines (properties.onbehalfof), bot pictures from their app icon (square, 4 px corners), bare bot cards with no bubble, and "Edited" above grouped edited messages.
- Spec §17 "Bot card actions"; harness --poll-test [--poll-vote=N].

Tests: cargo test --lib (498); live vote from OST on OST TEST 126 counted in Teams on winpc (Red 100% (1)).

Not yet: plain Action.Submit and messageBack (not invokes).
<!-- SECTION:FINAL_SUMMARY:END -->
