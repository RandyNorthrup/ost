---
id: TASK-0093
title: TUI channels and chats load their whole recent history
status: To Do
assignee: []
created_date: '2026-11-10T15:58:00Z'
labels:
  - bug
  - tui
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on the TUI UX tour (TASK-0010), 2026-11-10, tmux 120×40 on linuxlt.

Evidence: OST Test Team ▸ "OST test channel" and "OST test channel 2" show "No messages yet" (tour capture chan1/00.txt, chan2/00.txt), and `teams-cli read <channel>` prints "(no messages)". A probe showed the chat service's first page held only 4 messages, all ThreadActivity events (ThreadArchivalUpdate, UpdateFavDefault). The posts are on later pages, which `read_messages_data` never requests: it reads one page and ignores backward links. Scrolling up in General also stops after one page. The desktop reads these channels through `messages::read_timeline_page`, which follows the backward links.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Channels whose first page holds only events (OST test channel, OST test channel 2) show their posts in the TUI and in teams-cli read
- [ ] #2 Scrolling to the top of the messages pane loads older history, as the desktop does
<!-- AC:END -->
