---
id: TASK-0015
title: Desktop notifications for messages mentioning me
status: Done
assignee:
  - '@claude'
created_date: 2026-02-06 00:13
updated_date: '2026-11-05T19:24:00Z'
labels:
  - tui
  - feature
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a new message arrives that mentions the current user (by @name or @mention), show a desktop notification via the system notification daemon (e.g. notify-send on Linux). This lets the user keep the TUI in the background and still be alerted when someone needs their attention.

Should detect mentions in incoming messages from the trouter/websocket event stream and trigger a desktop notification with the sender name, channel/chat name, and a snippet of the message content.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A desktop notification appears when a new message mentions the current user
- [x] #2 Notification shows sender name, channel/chat name, and message snippet
- [x] #3 Notifications only fire for messages from others, not the user's own messages
- [x] #4 Works with notify-send or equivalent Linux notification mechanism
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Mention notifications in the desktop app (notify-rust over the freedesktop notification service, as notify-send uses).

Changes:
- event_hub: PushedMessage.mentions parsed from properties.mentions; channel reply ids drop the ";messageid=" suffix.
- Desktop backend: should_notify follows Teams defaults (never your own or the open chat; channel posts only when mentioned; optional "Only mentions" setting); mentions are titled "<sender> mentioned you"; channel banners name "Team > Channel".

Tests:
- cargo test (mentions_and_channel_replies, notifications_follow_teams_defaults)
- Live: an @mention from Teams web produced the Notify call "Randy Northrup mentioned you" with the text.
<!-- SECTION:FINAL_SUMMARY:END -->
