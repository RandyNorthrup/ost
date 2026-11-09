---
id: TASK-0079
title: 'Tab conversations as Teams: Show/Hide tab conversation'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T16:43:00Z'
updated_date: '2026-11-09T18:20:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams gives each app or website tab in a channel a conversation of its own: a Show tab conversation button in the channel header, in the expanded tab's header and in the tab's own window opens the tab's conversation beside it. OST lacks it (docs/spec/channel-tabs.md, chat-list-and-header.md 7.8).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Show/Hide tab conversation appears where Teams shows it (channel header, expanded tab header, tab window), with Teams' disabled 'Setting up conversation...' state
- [x] #2 The pane shows the tab's conversation from the same thread Teams uses, and replies sent from OST appear in Teams
- [x] #3 Verified side by side with Teams on winpc in OST Test Team
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Researched on winpc:
  - the btn-tab-conversation button, the end-slot Conversation pane and its empty state were measured;
  - Start conversation was captured: a POST of the tab-link post, a PUT of the thread property tab::{id} with replyChainId, and a PUT of rcmetadata ch;
  - the middle tier lists the root as the tab's messageId.
- Backend:
  - Tab gains can_converse, conversation (root) and icon (from the app definition);
  - tabs::start_conversation sends Teams' three requests, unit-tested against the captured bodies (the files property byte for byte, in Teams' key order);
  - channel_tab_change "converse" runs it;
  - the pane's thread loads through the thread-window registry (live, outbox lies).
- UI:
  - TabConversationPane.qml hosts a Conversation in thread mode (threadRoot: replies go to the thread; no draft or typing);
  - deeplink files render as Teams' tab card;
  - the header button sits before Meet now;
  - the tab window has the button and pane too, loaded by URL to avoid a QML type cycle that hung startup.
- Teams' channel header shows Find and Channel details only on Posts and has no people button. That is applied now; the rest of the channel header is TASK-0081.
- Verified live in OST Test Team:
  - a reply from OST's pane showed in Teams' pane;
  - Start conversation from OST (on a tab snapshot without one) posted the link and moved the Notes tab to the new conversation, which Teams then showed.
- Not shown by OST: Teams' "Setting up conversation..." state. OST reads the root with the tab list, so it never waits on it.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channel app tabs have their conversation, as in Teams: Show/Hide tab conversation opens it beside the tab, and Start conversation creates it.

Changes:
- tabs: Tab.can_converse / conversation / icon; start_conversation (Teams' captured requests); tests.
- files: deeplink attachments keep their tab id.
- backend: channel_tab_change "converse".
- QML:
  - TabConversationPane.qml (header, empty state, Start conversation, the thread as a chat);
  - Conversation thread mode;
  - the deeplink tab card;
  - the header button;
  - the tab window's button and pane;
  - Teams' channel-header visibility rules for Find, details and people.
- FluentIcon no longer touches a destroyed icon when its file arrives late.

Tests:
- `--tab-conversation-test` (reply shows in Teams) and `--tab-conversation-start-test` (start, then Teams shows the new conversation), live in OST Test Team.
- `--tab-window-test` shows the pane in the window.
- `--actions-test` (no regressions).
- lib tests: 367 passed.

Follow-up: the channel header's Meet now and More channel options (TASK-0081).
<!-- SECTION:FINAL_SUMMARY:END -->
