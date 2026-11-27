---
id: TASK-0371
title: >-
  Search as Teams: scoped suggestions after a scope pill, KQL filter pills and
  Ctrl+G go-to mode
status: To Do
assignee: []
created_date: '2026-11-27T20:58:00Z'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-0366 (title bar search suggestions). Teams desktop (winpc, 26304): picking a scope pill (e.g. Files) puts is:Files in the box, shows the chosen pill with x plus its nested filter pills (Files: from:, in:, filetype:; Messages: from:, in:, has: per ECS autosuggest.nestedFiltersConfig) and lists that domain's suggestions ("Suggested files", ECS domainScopingConfig zqCount/qfCount); typing a person puts a from:<person> pill first (People-centric search). The suggestion rows' hover actions (meeting Chat/Join/Recap, person search icon, chat pop-out) and the Ctrl+G go-to mode (Tip row) are also Teams'. TASK-0366 ships the pills as is:<Tab> scopes that open the results tab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Picking a scope pill shows Teams' scoped flyout: chosen pill with x, nested filter pills, the domain's suggestions; checked side by side with Teams desktop
- [ ] #2 from:/in:/filetype:/has: filter pills pick a person, place or type as Teams does and narrow the suggestions and results
- [ ] #3 Rows' hover actions (meeting Chat/Join/Recap, person search, chat pop-out) work as in Teams
- [ ] #4 Ctrl+G and the Tip row enter Teams' go-to mode (Type a chat or channel) with its suggestions
<!-- AC:END -->
