---
id: TASK-0365
title: >-
  Chat list as Teams: New items menu, Jump to Teams and channels, Discover,
  quick view unread counts, Drafts row, filter box, chat header Copilot history
status: Done
assignee:
  - '@claude-0365'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-28T00:07:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-01: Chat list "New items" menu has only "New chat"; fixed to match Teams desktop, checked side by side
- [x] #2 A-02: Chat list filter box: wording, position and clear button differ; fixed to match Teams desktop, checked side by side
- [x] #3 A-03: No "Jump to Teams and channels" bar at the bottom of the chat list; fixed to match Teams desktop, checked side by side
- [x] #4 A-05: Chat list Quick views: no "Discover" feed; fixed to match Teams desktop, checked side by side
- [x] #5 A-06: Chat list Quick views: "Drafts" is hidden when there are no drafts; fixed to match Teams desktop, checked side by side
- [x] #6 A-07: Quick view rows show no unread state or count; fixed to match Teams desktop, checked side by side
- [x] #7 A-21: Chat header ··· has no "View Copilot history"; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- PR #56 (task-0365-discover): AC 4, the Discover quick view and feed. Checked live as OST Test 2 on testpc1 (WSLg) and on linuxlt with a head build: feed, Teams' card menu, hide channel (all covered cards) + Don't show post from accordion + Undo on the server, feedback, reactions with no chat open. Twelve Codex findings over six rounds were fixed and resolved.
- testpc2 filled its C: drive during this work (two ~9 GB build folders were part of it); the coordinator is freeing it.

- PR #52 (merged): ACs 1, 2, 3, 5, 6, 7, checked live on testpc2 (OST test2 / ost-test1) beside Teams web and desktop. Research: Teams web via CDP and the 26304 bundles (slice providers, Nb, sticky filter, jumper, viewSummaryHistory). ost-test1 @mentioned OST Test 2 and replied in a followed thread: Teams and OST both showed Mentions 1 and Followed threads 1.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chat list and chat header as Teams (audit A items 1, 2, 3, 5, 6, 7, 21), in two PRs.

PR #52 (merged): New items ▾ (New message, in new window, New channel with Create a channel's team picker, New storyline post | Join team, New team | Join communities | New section); the filter box above the pills with Teams' placeholder, Clear filter text, focus line, debounce, marks and slice filtering; the Jump to Teams and channels bar; Quick views by Teams' slice rules (Drafts always, with its empty view; Saved/Followed only with items; Mentions/Followed bold with count badges, counted at sign-in and on 48:threads / 48:saved pushes; a never-used 48:saved reads as empty); View Copilot history first in More chat options (main window, pop-out chats and the Chat app window).

PR #56: Quick views ▸ Discover: CSA discover feed, cards as channel posts with Teams' reasons, Is this useful?, its ··· items (Don't show this post / author / channel, hidden cards with Undo), the Don't show post from accordion, You’re all caught up, image viewer, reply in thread with quotes.

Verified live beside Teams web and Teams desktop (testpc2) as OST Test 2 and ost-test1; harness --chatlist-parity-test, --copilot-history-test, --discover-test. Not built: the Reminders quick view (belongs with TASK-0363's Remind me) and Discover's "New updates" poll.
<!-- SECTION:FINAL_SUMMARY:END -->
