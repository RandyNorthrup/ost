---
id: TASK-0046
title: >-
  Conversation header as Teams: call controls per chat kind, roster count, More
  chat options
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-07T17:49:00Z'
labels:
  - desktop
  - header
dependencies: []
references:
  - docs/spec/chat-list-and-header.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Header gaps from docs/parity/gaps-chat-messages.md (P1), per docs/spec/chat-list-and-header.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 1:1: one sticky Audio/Video call button (last choice remembered) + chevron; group: Meet now with Audio call; meeting chat: Join and Meeting details
- [ ] #2 Roster count button and More chat options ··· as Teams, with the header breakpoints (640/720/834)
- [x] #3 Rename pencil only for group chats (250 chars, no ':'), saved as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Group header measured live; tabs per chat kind; rename pencil and popover (PUT topic, verified) [AC3]; roster count button; More chat options with Schedule meeting, Mark as unread, Copy link.
- Left: Meet now / Join (group and meeting calls), 1:1 sticky audio/video button, header breakpoints (640/720/834), the remaining ··· items (Open in new window, Share screen, Move to section, Mute, Remove chat history, Leave, Manage notifications), Add a tab.

- Meet now and group calls, verified live against Randy's Teams web:
  - Meet now creates a huddle as Teams does (no ring);
  - Audio call rings the members;
  - Join enters the chat's live call: both rosters show both people, audio flows, and the mixer's re-offer is answered with its own content type (sdp-ngc-1.0).
- While a call is going (thread liveness `awareness_conversationLiveState`), the header shows the measured gradient pill: live roster with stacked 24 px avatars, plus Join; in the call, only the roster.
- The chat list shows the 14 px sound-wave on the row.
- Start rows name the initiator from the roster ("Randy Northrup started a meeting.").
- Someone else's Meet now (HuddleMeetingStart push) shows Teams' toast: chat name, "{name} started a meeting", Join / Message. Message was verified via the notifier.
- Left for the toast: the chat-mute and meeting-started-setting prechecks (OST has neither setting yet), and the MeetingStartedReminder sound.

- Mute / Unmute (alerts property, measured on winpc), in the header ··· and in the new chat-list row menu. The row menu has right-click and the hover ···, with Mark as read/unread, Mute/Unmute and Copy link.
- Muted rows look as in Teams. Muted chats count toward no badge and notify only for @mentions, and the Meet now toast skips them. Verified with --mute-test: server state round-trips, then unmuted.

- 1:1 sticky call button as Teams: Video call / Audio call (chevron menu with shortcuts, Alt+Shift+V added). The last choice roams via userPersonalSettings.chatSettings.mruChatHeaderCallOption; winpc's Teams picked up OST's value.
- A Video call offers the camera from the start. Verified live: Randy's web got OST's video on answering. ost-test1's choice was restored to Audio call afterwards (examples/header_call_choice.rs).
- Left for AC1: the meeting chat header (Join, Meeting details).
<!-- SECTION:NOTES:END -->
