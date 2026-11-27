---
id: TASK-0357
title: 'Settings and title bar as Teams: Denoising, About date, ended Premium trial'
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
- [ ] #1 B-12: Settings > Devices > Video: "Denoising" switch missing, as Teams desktop does it, checked side by side
- [ ] #2 B-14: Settings > About: "last checked" date uses a two-digit year, as Teams desktop does it, checked side by side
- [ ] #3 B-15: Title bar: Teams Premium pill and menu rows for an ended (canceled) Premium trial, as Teams desktop does it, checked side by side
<!-- AC:END -->
