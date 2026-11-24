---
id: TASK-0173
title: Add a tab (+) to chats, channels and meetings as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T09:43:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' '+' adds an app tab; OST can't add tabs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 '+' opens Teams' Add a tab picker in chats, meeting chats and channels (channel menu first), as measured on winpc
- [x] #2 A Website tab added or removed in OST appears or disappears for everyone, with Teams' requests and its 'I added a tab' post
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (3e52e9f), merged as e723e84; spec docs/spec/add-a-tab.md.
- Verified on linuxlt: website tab added/removed in OST group test and General; winpc Teams showed and removed it.
- Merged build re-checked: picker and Website dialog with Teams' invalid-URL error.
- Other apps' tab configuration pages and the channel menu's page/list items moved to TASK-0198 (needs TASK-0053).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Add a tab as Teams in chats, meeting chats and channels.

- "+" after the tabs; channels show Teams' menu (New page, Existing page, New list, Existing list, Apps), then the picker.
- The picker is the in-context Store in tab mode: the conversation's tab apps (most recently used first, See all / See less), collections, search.
- Website: Teams' own configuration, URL rule and "Post to the chat about this tab"; Save sets the thread's tab:: property, posts the link card, then sets the replyChainId, exactly as captured.
- Remove sets the property to null (chats and channels), as Teams does now. A chat's own tabs are read from its thread, with Teams' menus and +N overflow.

Tests: 576 library tests pass (7 new, including an exact-request test); live add/remove checked against winpc Teams.

Follow-up: TASK-0198 (other apps' configuration pages, channel page/list items).
<!-- SECTION:FINAL_SUMMARY:END -->
