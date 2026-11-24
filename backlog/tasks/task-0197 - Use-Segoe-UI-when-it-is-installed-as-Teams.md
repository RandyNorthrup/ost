---
id: TASK-0197
title: Use Segoe UI when it is installed, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-16T05:21:00Z'
updated_date: '2026-11-16T10:03:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams uses Segoe UI. OST can't ship it (Windows licence), so it ships Microsoft's open Selawik; when Segoe UI is installed on the machine, OST should use it as Teams does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With Segoe UI installed OST's text uses it; without it, Selawik
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Checked on linuxlt with Segoe UI copied from winpc for the test (then removed): OST's text switched to Segoe UI; without it Selawik. Captures in the session scratchpad segoe/shots.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST uses Segoe UI, Teams' font, when the machine has it installed, and the bundled Selawik otherwise.

- Theme.font picks "Segoe UI" when Qt.fontFamilies() lists it; every text in OST reads Theme.font.
- Verified on linuxlt with and without Segoe UI installed (test copy removed afterwards; OST never ships it).
<!-- SECTION:FINAL_SUMMARY:END -->
