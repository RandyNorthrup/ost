---
id: TASK-0367
title: >-
  Activity and Calendar as Teams: missed-call routing, Activity menu and filter,
  Add calendar, open at current time, organizer photo
status: To Do
assignee: []
created_date: '2026-11-27T18:19:00Z'
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
- [ ] #1 A-11: Missed-call activity opens the chat instead of Calls ▸ History; fixed to match Teams desktop, checked side by side
- [ ] #2 A-12: Activity "···" menu: only "Mark all as read", no shortcut, no "Notification settings"; fixed to match Teams desktop, checked side by side
- [ ] #3 A-13: Activity filter box: placeholder and placement differ; fixed to match Teams desktop, checked side by side
- [ ] #4 A-14: Calendar navigation pane: no "Add calendar", and the mini month can't be collapsed; fixed to match Teams desktop, checked side by side
- [ ] #5 A-15: Calendar opens at 8 AM instead of scrolling to the current time; fixed to match Teams desktop, checked side by side
- [ ] #6 A-22: Event peek card: organizer shown as initials instead of their photo; fixed to match Teams desktop, checked side by side
<!-- AC:END -->
