---
id: TASK-0093
title: TUI reads message history as Teams does and loads older pages
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:58:00Z'
updated_date: '2026-11-10T16:02:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010).

The TUI asked for `/messages?pageSize=50` without Teams' `view=msnp24Equivalent` and `startTime=1`, and never followed a page's backward link, so it only ever had the newest page. (The tour's "No messages yet" in OST test channel and OST test channel 2 turned out to be right: with Teams' parameters and 200 per page, the service returns only 4 thread events for each, ThreadArchivalUpdate and UpdateFavDefault, left from the archive/restore tests.) Scrolling to the top still doesn't load older messages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The TUI requests a conversation's messages with Teams' parameters (the desktop's messages_url) and follows backward links until it has a screenful
- [x] #2 Scrolling to the top of the messages pane loads the next older page, as the desktop does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- read_messages_data now uses messages::messages_url and backward_token: up to 5 pages, until `limit` text messages. Verified the empty test channels hold only 4 events (teams-cli read with -l 200).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The TUI now reads message history as Teams does and loads older messages when you scroll past the top.

Changes:
- `read_messages_data` asks with the desktop's `messages::messages_url` (Teams' `view=msnp24Equivalent`, `startTime=1`) instead of a bare `/messages?pageSize=50`. It follows each page's backward link (`backward_token`) until it has `limit` text messages or the history ends.
- Messages pane: Up on the oldest message asks for 50 more ("Loading older messages…") and keeps the selection on the message that was at the top. A load that brings nothing new marks the history complete, so no further requests go out. Opening another conversation starts again from its newest page.

Tests:
- New `scrolling_past_the_top_asks_for_older_messages`.
- Live: OST group test scrolls to its very first message ("OST test 27: group chat started from OST") with no spurious loads. No test conversation is longer than one load, so the older-page path is covered by the unit test.
- The tour's empty channels were correct: they hold only 4 thread events.
<!-- SECTION:FINAL_SUMMARY:END -->
