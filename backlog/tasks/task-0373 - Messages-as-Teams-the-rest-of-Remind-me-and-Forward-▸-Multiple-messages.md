---
id: TASK-0373
title: 'Messages as Teams: the rest of Remind me and Forward ▸ Multiple messages'
status: To Do
assignee: []
created_date: '2026-11-27T21:42:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-0363 (its second PR added Remind me, the Reminders quick view, Ask Copilot and Forward ▸ Multiple messages in chats). What Teams does that OST doesn't yet, from Teams 26304 (docs/spec/message-actions.md §13-15):
- Channel posts: Forward is a split item there too (enableForwardMultiselectChannelPane): picking posts in the posts list, with the same selection bar.
- Leaving a chat mid-selection: Teams asks "Discard and leave" (message_list_multiselect_discard_event_*); OST drops the selection.
- Reminders view rows: More options also has Save / Unsave this message.
- The saved bookmark and reminder alarm in channel posts and replies (OST shows neither in channel views).
- Ask Copilot in a channel post's view (L2) and thread pane.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Channel posts: Forward ▸ Multiple messages works as in Teams, checked side by side
- [ ] #2 Leaving a chat while picking messages asks Discard and leave, as Teams
- [ ] #3 Reminders rows' More options include Save / Unsave this message
- [ ] #4 Channel posts and replies show the Saved and reminder icons as Teams
- [ ] #5 Ask Copilot is offered in a channel post's view and thread pane where Teams offers it
<!-- AC:END -->
