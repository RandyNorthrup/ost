---
id: TASK-0046
title: >-
  Conversation header as Teams: call controls per chat kind, roster count, More
  chat options
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-09T12:49:00Z'
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
- [x] #1 1:1: one sticky Audio/Video call button (last choice remembered) + chevron; group: Meet now with Audio call; meeting chat: Join and Meeting details
- [x] #2 Roster count button and More chat options ··· as Teams, with the header breakpoints (640/720/834)
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

- Meeting chat header: Join (measured; hidden when cancelled, disabled while in the meeting); tabs Chat, Shared and Recap; no rename pencil, Meet now or call pill. Verified: --meeting-chat-test joined the OST calendar test meeting from the header.
- Chats with isemptyconversation aren't listed unless open, as in Teams.
- Left: Meeting details (opens the event page, TASK-0050); the "+4" tab overflow (Attendance, Breakout Rooms, Q&A, Meeting Whiteboard); Add a tab; header breakpoints; the remaining ··· items.

- Header breakpoints as measured on winpc (narrowed via VNC):
  - below 720 the roster count moves into ··· as Participants;
  - below 640 the title is 14 px with a tab dropdown under it, chat details moves into ··· as "In this chat" (Alt+P) and only Find stays inline; below 480 Find goes too;
  - live-roster avatars show only from 834;
  - the right side packs from the edge (···, context buttons, divider, actions).
- Tabs overflow by width into "+N" with a menu.
- Verified with --breakpoints-test at 892/781/681/604/460 for group and 1:1 chats, including the ··· menus.

- 2026-11-09:
  - Added the meeting chat's Meeting details (chat-meeting-details, TextBulletList, after the roster count; inline from 640 wide, else in ···). It opens the meeting in OST's calendar: the meeting's week, then its card. Teams' full event page is TASK-0050.
  - The header ··· gained Move to section ▸ (with New section).
  - Verified on linuxlt (--meeting-details-test) in the "OST calendar test" meeting chat.
- The 1:1 sticky call button, group Meet now / Audio call / Join, the roster count, ··· and the 640/720/834 breakpoints were built and verified live earlier (28fbb5d and the breakpoints harness).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The chat header matches Teams' controls for each chat kind.

Changes (this round):
- The meeting chat's **Meeting details** button: Teams' TextBulletList, after the roster count, inline from 640 wide, else in ···. It opens the meeting in OST's calendar (its week, then its card).
- The header ··· gained **Move to section ▸** (Favorites, your sections, New section), on Teams' folder API.
- Earlier work covered the rest:
  - the 1:1 sticky Audio/Video button with its last choice (`mruChatHeaderCallOption`) and More call options;
  - group chats' Meet now / Audio call and Join while a call is on;
  - the roster count and its tooltips;
  - the rename pencil;
  - the 640/720/834 breakpoints that move controls into ···.

Tests: live on linuxlt (`--meeting-details-test`): the header, Meeting details opening the meeting's card in the calendar, and the header ··· menu.

Still to come (TASK-0075): Open in new window, Share screen and Remove chat history in the header ···. Teams' full meeting page is TASK-0050.
<!-- SECTION:FINAL_SUMMARY:END -->
