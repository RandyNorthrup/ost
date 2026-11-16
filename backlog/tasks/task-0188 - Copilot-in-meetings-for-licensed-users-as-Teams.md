---
id: TASK-0188
title: Copilot in meetings for licensed users as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-16T23:39:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST shows meeting options' Allow Copilot and a read-only AI menu; ost-test1 has a Copilot licence since 2026-11-15.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The in-meeting Copilot pane and its licensed states work as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Built by a subagent (e07b90b, merged): Copilot button only with a licence (disabled when meeting options turn it off), Teams' "Start transcription to use Copilot" alert and language step, the 320-wide pane hosting Microsoft 365 Copilot as Teams does with the meeting context, Alt+C. Checked live: transcript started, real answers from the meeting's chat, stop passed to the app, OST left every run.
- Leftovers: TASK-0211.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Copilot in meetings for licensed users as Teams: button, transcription alert and start, the side pane with the meeting context, real answers checked live. Harness --join-copilot. Follow-up TASK-0211.
<!-- SECTION:FINAL_SUMMARY:END -->
