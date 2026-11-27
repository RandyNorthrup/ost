---
id: TASK-0354
title: >-
  Calls app controls as Teams: dial pad, parked calls, forwarding, audio device,
  call delegation, speed dial
status: To Do
assignee: []
created_date: '2026-11-27T17:31:00Z'
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
- [ ] #1 B-01: Calls app: dial pad and number entry for Teams Phone users, as Teams desktop does it, checked side by side
- [ ] #2 B-02: Calls app: "Parked calls" button under the dial pad, as Teams desktop does it, checked side by side
- [ ] #3 B-03: Calls app: call forwarding quick menu ("Don't forward ▾"), as Teams desktop does it, checked side by side
- [ ] #4 B-04: Calls app: audio device button ("Custom Setup ▾" with Device settings), as Teams desktop does it, checked side by side
- [ ] #5 B-05: Calls app: Intelligent call delegation banner and onboarding pane, as Teams desktop does it, checked side by side
- [ ] #6 B-10: Calls app: speed dial empty-state illustration, as Teams desktop does it, checked side by side
<!-- AC:END -->
