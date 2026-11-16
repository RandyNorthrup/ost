---
id: TASK-0207
title: Loop page extras as Teams
status: To Do
assignee: []
created_date: '2026-11-16T20:42:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0205 left of Teams' Loop host (docs/spec/loop-host.md): "See who has access" opens the link in the browser instead of Teams' permissions panel; Loop doesn't get Teams' presence colours, @-mention people suggestions, formatting toolbar, nested Loop components, telemetry sink or trusted-types policy; Teams' dark and high-contrast Loop themes aren't measured (OST sends the theme name with the light values); a Page tab without a link that OST didn't create shows the loading page indefinitely.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 See who has access opens Teams' permissions panel
- [ ] #2 Mentions, presence, the formatting toolbar and nested Loop components work in OST's Loop pages as in Teams
- [ ] #3 Loop pages use Teams' dark and high-contrast themes, measured on winpc
- [ ] #4 A Page tab without a link behaves as in Teams
<!-- AC:END -->
