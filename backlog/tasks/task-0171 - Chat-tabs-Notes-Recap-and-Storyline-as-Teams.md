---
id: TASK-0171
title: Chat tabs Notes, Recap and Storyline as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T11:49:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In OST these tabs only say they aren't available yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Chats and meeting chats list Notes, Recap and Storyline as Teams (1:1, group, self and meeting chats differ)
- [x] #2 Recap shows Teams' pages: no recap in a chat; in a meeting chat its Shared files, AI summary, Mentions and Transcript pages
- [x] #3 Notes finds or creates the chat's Loop page as Teams and draws Teams' header, loading, deleted and error pages
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (3e633cd), measured in Teams on the web as ost-test1; spec docs/spec/chat-tabs.md.
- Verified on linuxlt: tab lists for group, 1:1, self and meeting chats; Recap matches Teams in OST group test and a meeting chat; Notes reads OST group test's existing page.
- Opening Notes in Teams on the web created OST group test's (empty) notes page and its "Notes have been created" row; kept, as Teams would.
- Showing the Loop and Storyline pages: TASK-0201. Not covered: a recap with real content (no test meeting has one), the Copilot button, More options' items.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat tabs Notes, Recap and Storyline as Teams.

- Which chats get which tab (Storyline in 1:1 and your own chat; no Notes in meeting chats; Notes added to your own chat).
- Notes: src/api/chat_notes.rs reads the thread's fileReferences and creates the Loop page as Teams (POST /v1/threads/{id}/files); Teams' header with lock, loading, deleted (Create new) and error (Retry) pages; the "Notes have been created" row opens the tab.
- Recap: native, with Teams' illustrations; meeting chats' Shared files card, AI summary / Mentions / Transcript pills.
- Storyline: Teams' Viva Engage page for the right person.

Tests: 4 new unit tests; --chat-tab-test harness. Follow-up: TASK-0201 (the Loop and Storyline pages).
<!-- SECTION:FINAL_SUMMARY:END -->
