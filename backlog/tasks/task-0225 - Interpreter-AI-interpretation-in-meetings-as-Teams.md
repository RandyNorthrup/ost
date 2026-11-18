---
id: TASK-0225
title: Interpreter (AI interpretation) in meetings as Teams
status: To Do
assignee: []
created_date: '2026-11-18T23:07:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/new-meeting-controls.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0214/0208: Teams shows Interpreter in meetings when the meeting policy's aiInterpreter is Enabled and the user has a Microsoft 365 Copilot licence (an organizer can turn it on for everyone). OST has no AI interpretation yet. Only ost-test1 has a Copilot seat; the tenant's Copilot trial has unassigned seats.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Interpreter shows in OST's meeting controls exactly when it shows in Teams
- [ ] #2 Turning Interpreter on in OST gives the same interpreted audio and settings as Teams, verified live between test accounts
<!-- AC:END -->
