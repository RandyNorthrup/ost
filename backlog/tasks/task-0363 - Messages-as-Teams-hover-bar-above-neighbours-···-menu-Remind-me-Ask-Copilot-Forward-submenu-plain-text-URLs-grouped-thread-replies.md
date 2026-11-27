---
id: TASK-0363
title: >-
  Messages as Teams: hover bar above neighbours, ··· menu Remind me / Ask
  Copilot / Forward submenu, plain-text URLs, grouped thread replies
status: To Do
assignee: []
created_date: '2026-11-27T18:19:00Z'
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
