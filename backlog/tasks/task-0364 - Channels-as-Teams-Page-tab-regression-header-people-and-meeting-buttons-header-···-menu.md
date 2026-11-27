---
id: TASK-0364
title: >-
  Channels as Teams: Page tab regression, header people and meeting buttons,
  header ··· menu
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
- [ ] #1 A-18: Channel "Page" tab is missing; fixed to match Teams desktop, checked side by side
- [ ] #2 A-19: Channel header: no people button, and "Meet now" instead of Teams' meeting button; fixed to match Teams desktop, checked side by side
- [ ] #3 A-23: Channel header ··· menu: items differ (no "View meetings" or "Mark as unread"; extra admin items); fixed to match Teams desktop, checked side by side
<!-- AC:END -->
