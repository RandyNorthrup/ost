---
id: TASK-0096
title: TUI keeps every @mention's name in the message text
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T15:58:00Z'
updated_date: '2026-11-10T16:07:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010). In OST group test, "OST test 54: mention for check" shows with the mentioned person missing (group/12.txt), while the next message shows "OST test 54: mention for Randy Northrup check". Other mentions in General (channel, team and tag mentions, OST TEST 60–70) keep their names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every mention in the tour's chats shows the mentioned name
- [x] #2 The cause is covered by a unit test with the message's real content
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Not a rendering bug.

The message the tour flagged, "OST test 54: mention for check", has no mention in its content: the service holds `<p>OST test 54: mention for check</p>` with `mentions: []`. It was an early test where the mention was dropped when the message was sent, and Teams shows the same text. Every mention the service does hold renders with its name, including the two-part "Randy" + "Northrup" mention in its neighbour.

Tests: new `mentions_keep_their_names` uses that message's real content and properties.
<!-- SECTION:FINAL_SUMMARY:END -->
