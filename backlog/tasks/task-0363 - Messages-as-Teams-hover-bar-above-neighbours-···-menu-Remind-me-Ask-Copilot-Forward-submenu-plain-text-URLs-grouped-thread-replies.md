---
id: TASK-0363
title: >-
  Messages as Teams: hover bar above neighbours, ··· menu Remind me / Ask
  Copilot / Forward submenu, plain-text URLs, grouped thread replies
status: In Progress
assignee:
  - '@claude-0363'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-27T18:34:00Z'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A-09: Message hover bar is drawn underneath the message above it; fixed to match Teams desktop, checked side by side
- [ ] #2 A-10: Message ··· menu lacks "Remind me", "Ask Copilot" and Forward's split submenu; fixed to match Teams desktop, checked side by side
- [ ] #3 A-04: OST turns plain-text URLs in received/sent messages into links; Teams shows them as text; fixed to match Teams desktop, checked side by side
- [ ] #4 A-20: Consecutive replies by the same person in a channel thread aren't grouped; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. A-09: raise the hovered message above its neighbours in Conversation's BottomToTop list (z while the bar shows) and make the bar's HoverHandler blocking, so the message above neither covers the bar nor takes the hover.
2. A-04: Teams' renderer links only <a> elements (TextDeserializer 721466 passes text through); stop linkifying bare URLs in message HTML (keep it for status notes).
3. A-20: Teams' worker groups channel replies (92502 d: same sender/app, previous not deleted, ordinary messages, <=5 min, never the first reply; summary view's first shown reply keeps its header); avatar+indicator hidden (visibility), header gone, body 8 under the previous. Apply in ChannelPosts (L1) and PostThread (L2).
4. A-10: research Remind me (rcmetadata r/dr, 48:reminders), Ask Copilot (BizChat side pane, ChatHighlights prompt) and Forward split (This message / Multiple messages + multiselect forward mode); implement in a second PR.
5. Live checks side by side with Teams (web as OST Test 2 / desktop on testpc2) and OST on linuxlt as OST Test 2/3.
<!-- SECTION:PLAN:END -->
