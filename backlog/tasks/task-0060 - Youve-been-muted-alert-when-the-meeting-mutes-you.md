---
id: TASK-0060
title: '"You''ve been muted" alert when the meeting mutes you'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T16:00:00Z'
updated_date: '2026-11-08T16:13:00Z'
labels:
  - calls
  - meetings
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the organizer mutes you (Mute all or per person), Teams shows a callout under the toolbar: mic-off glyph, "You've been muted" title, body text, close button and an Unmute button (Teams web guest: callingAlertActionButton_MicMutedRemotely). OST now mutes locally without telling you. Measure the callout on winpc and build it natively.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 When the meeting mutes you, the callout appears as on winpc (position, size, text, buttons)
- [x] #2 Unmute in the callout unmutes as the Mic button does; the close button dismisses it
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' "You've been muted" alert in meetings.

- Trigger as Teams (micMutedRemotely): the meeting mutes you while you're unmuted and have audio; closes after 30 s, on dismiss, or when you're unmuted.
- MutedNotice.qml from the Fluent tokens Teams styles it with (same family as RoomNotice, measured on winpc); Unmute toggles the mic like the Mic button.
- Backend: call_muted_by_meeting and call_muted_remotely from our endpoint's server mute.

Verified live on linuxlt (OST joined unmuted into a meeting that server-muted it).
<!-- SECTION:FINAL_SUMMARY:END -->
