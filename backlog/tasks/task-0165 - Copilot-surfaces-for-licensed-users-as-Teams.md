---
id: TASK-0165
title: Copilot surfaces for licensed users as Teams
status: Done
assignee: []
created_date: '2026-11-16T00:26:00Z'
updated_date: '2026-11-21T15:20:00Z'
labels:
  - desktop
  - copilot
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With a Copilot licence (ost-test1 since 2026-11-15) Teams shows Copilot in the app bar and at the top of the chat list, 'Search or ask Copilot (Ctrl+E)' in the search box, and Settings ▸ Privacy's 'Delete Copilot activity history' card (with 'Learn how to delete Copilot activity history' and 'Open Copilot activity history'). OST shows none of these. Compose's Write with Copilot is TASK-0164.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST shows Copilot where Teams does for licensed users only (app bar, chat list, search placeholder), measured on winpc
- [x] #2 Privacy shows 'Delete Copilot activity history' as Teams' card with its links
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (agent setF) Teams 26304 read and measured on winpc (docs/spec/settings.md "Copilot surfaces"). Built:
  - Licence and ECS flags in compose_copilot_state (licensed, deleteHistory, search, chatList, settingsToggle, the two Microsoft URLs).
  - App bar: Copilot is a pinned personal app from the service (b5abf2ae), already listed; OST shows it as Teams does.
  - Chat list: the Copilot row only with ECS chatList/simpleCollab entry points, the Copilot app installed for you and shouldShowMetaOSCopilotApp not false (Settings ▸ Chats ▸ Copilot now drives it; that switch only for licensed users with the app, ECS enableMetaOSCopilotToggleInSettings).
  - Search box: "Search or ask Copilot (Ctrl+E)" / focused "Look for people, messages, files and more or ask Copilot" (licence + autosuggest.enableSerpCatalystEntrySuggestion); a query of 2+ words offers "Ask Copilot about <b>query</b>" first (Teams' row: 32 px circle, glyph, 50 tall); choosing it opens the results with the Microsoft 365 Copilot app in the right pane (scope Search, entry SearchAutosuggestAskCopilot, cmmid cmmi7lmhneb, reference = SHA-256 of the search session, frame chat/sessionanchor/<ref>), told the Search context and handed the query (SearchPrompt with Teams' CopilotSearch annotation) once the app has started (api::meeting_copilot::launch_search).
  - Privacy: Delete Copilot activity history card (note + Learn how… link, Open Copilot activity history button with the open glyph).
- Verified live on linuxlt (ost-test1, --setf-test): the search placeholder, the Ask Copilot suggestion, the results with Copilot answering "what meetings do I have today" (it listed OST TEST 240's meeting), the chat list's Copilot row, the Privacy card. Teams on winpc: the same query gave the same pane and answer.

- 2026-11-21 merged (10fb14c, 0824252).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Copilot surfaces for licensed users as Teams: the Copilot app on the app bar (pinned by the service), the chat list's Copilot row (with Settings ▸ Chats ▸ Copilot), the search box's "Search or ask Copilot (Ctrl+E)" placeholder and its "Ask Copilot about …" suggestion opening the Microsoft 365 Copilot pane, and Privacy's Delete Copilot activity history card; all only with a Copilot licence. Verified live on linuxlt as ost-test1 and side by side with Teams on winpc (same query, same pane and answer).
<!-- SECTION:FINAL_SUMMARY:END -->
