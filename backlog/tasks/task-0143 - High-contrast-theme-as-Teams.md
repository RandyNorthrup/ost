---
id: TASK-0143
title: High contrast theme as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T03:06:00Z'
updated_date: '2026-11-16T04:16:00Z'
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
- [x] #1 Theme offers High contrast after Classic, as in Teams
- [ ] #2 Every OST view in High contrast shows Teams' high-contrast colours for backgrounds, text, strokes, hover/selection, links and disabled states
- [x] #3 Switching between all five themes applies at once and is kept
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams in High contrast on winpc (tokens, rows, menus, switches, avatars, pictures)
2. Theme: highContrast, 3-way pick, onFill for text on light fills, transparentStroke, checkedFill, link
3. Script every QML colour (role + state) to its High contrast value; regenerate deterministically
4. Hand-fix what the rule can't see (rail, avatars, bubbles, contrast pictures)
5. Compare views with Teams; confirm Light/Dark unchanged
6. Calls and meetings in High contrast against a live Teams call
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-15: Teams' High contrast measured on winpc (theme switched there; restore it to Follow OS when done).
  - Hover, selection and checked controls are #1AEBFF with black ink.
  - Primary buttons: white with black text. Links: #FFFF00. Disabled: #3FF23F.
  - TransparentStroke is white, so bubbles, menus, pills and inputs get outlines.
  - Avatars sit in a 2 px white ring; the selected rail item is a full 68 x 44 cyan fill.
  - Teams swaps its Settings pictures for -contrast SVGs.
- OST: Theme.highContrast (with dark on) and pick(light, dark, hc). scratchpad hc_rewrite.py gave 496 picks and 230 literals High contrast values, wrapped 1086 text/icon colours in theme.onFill, and added 27 selected states and 29 input outlines. hc_manual.py and hc_post.py hold the hand edits.
- Checked: shell, chat list, conversation, every Settings page, menus, calendar, OneDrive, Store, People, Downloads, mobile app dialog. A Light-mode shot is pixel-identical to the one before the change.
- Left: calls and meetings in High contrast against Teams.
<!-- SECTION:NOTES:END -->
