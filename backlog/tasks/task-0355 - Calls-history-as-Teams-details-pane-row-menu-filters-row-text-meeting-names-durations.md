---
id: TASK-0355
title: >-
  Calls history as Teams: details pane, row menu, filters, row text, meeting
  names, durations
status: To Do
assignee: []
created_date: '2026-11-27T17:32:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope B), which compared Teams desktop on winpc (ost-test1, read over CDP) with OST main 7d1c3a38 on linuxlt. Each acceptance criterion is one verified gap. The full entry for each (what Teams does, what OST does, severity, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditB.md, under its B-number, with screenshots in audit/shots-B/ (t-* Teams, o-* OST).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 B-06: Calls app: clicking a history row opens a Details pane, as Teams desktop does it, checked side by side
- [ ] #2 B-07: Calls app: row hover shows ··· (Chat, Remove from view, Report call), as Teams desktop does it, checked side by side
- [ ] #3 B-08: Calls app: History "Filter by name or number" and the Voicemail filter, as Teams desktop does it, checked side by side
- [ ] #4 B-09: Calls app: history row text, duration placement and dates, as Teams desktop does it, checked side by side
- [ ] #5 B-13: Calls history: meeting calls named by a person, and extra "Unknown" rows, as Teams desktop does it, checked side by side
- [ ] #6 B-22: Calls history: durations are rounded, Teams truncates, as Teams desktop does it, checked side by side
<!-- AC:END -->
