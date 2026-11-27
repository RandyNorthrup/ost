---
id: TASK-0360
title: Network indicator call feedback prompt as Teams
status: To Do
assignee: []
created_date: '2026-11-27T17:48:00Z'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' network-strength popover sometimes (about 1% of calls) asks for call feedback. OST left it out under TASK-0059 because it must not submit call feedback to Microsoft, but the call-quality survey now handles the same case by opting in and opening a GitHub issue (Report a problem). Found by the 2026-11-27 recheck of the work page's left-out list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The network indicator popover shows Teams' feedback prompt under Teams' rule and sampling rate, and answering it routes to OST's Report a problem (GitHub) the way the call-quality survey does; nothing is sent to Microsoft
<!-- AC:END -->
