---
id: TASK-0060
title: '"You''ve been muted" alert when the meeting mutes you'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-08T16:00:00Z'
updated_date: '2026-11-08T16:01:00Z'
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
- [ ] #1 When the meeting mutes you, the callout appears as on winpc (position, size, text, buttons)
- [ ] #2 Unmute in the callout unmutes as the Mic button does; the close button dismisses it
<!-- AC:END -->
