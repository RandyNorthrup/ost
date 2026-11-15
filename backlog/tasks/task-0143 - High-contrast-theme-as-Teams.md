---
id: TASK-0143
title: High contrast theme as Teams
status: To Do
assignee: []
created_date: '2026-11-15T03:06:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings ▸ Appearance ▸ Theme offers "High contrast": Fluent's high-contrast palette (black backgrounds, white text and strokes, #1AEBFF for hover, selection and brand fills, #FFFF00 links, #3FF23F disabled). OST's Theme has light and dark values only, about 60 tokens plus about 480 inline theme.pick(light, dark) colours. Light values don't map one-to-one to high contrast: #F5F5F5 is black as a background but #1AEBFF as a hover. So each token and inline colour needs its own high-contrast value. Teams' Fluent token values for Light, Dark and High contrast were dumped from winpc on 2026-11-14 into docs/spec/teams-tokens-*.json.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Theme offers High contrast after Classic, as in Teams
- [ ] #2 Every OST view in High contrast shows Teams' high-contrast colours for backgrounds, text, strokes, hover/selection, links and disabled states
- [ ] #3 Switching between all five themes applies at once and is kept
<!-- AC:END -->
