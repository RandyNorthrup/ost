---
id: TASK-0255
title: Desktop fixes from the release screenshot pass
status: Done
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T17:39:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Smaller issues seen while preparing the 0.2.0 release.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dark theme calendar draws the hours before the working day in Teams' dark colours, not white
- [x] #2 NOTICE.md describes the logo as it is
- [x] #3 ost-desktop --version and --help print the version and usage and exit, without starting the app or harness mode
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (fixV): Teams' Calendar is the Outlook hosted calendar frame; its palette measured on winpc in light and dark (Teams switched to Dark for a minute, then back to Follow OS): neutralPrimarySurface #FFFFFF/#292929 (days), neutralLighterAlt #FAFAFA/#242424 (past days, hours outside the working day), neutralTertiaryAlt #D1D1D1/#5C5C5C (lines). OST drew theme.hc light values in dark.
- Logo: layout A (make_logo.py default): a wide OST plate in front of three people, gradient-shaded; NOTICE.md said "two people", make_logo.py's docstring still called B the default.

- Verified live on linuxlt: OST Test 3 with --theme=dark, Calendar work week scrolled to 5 AM: the hours before 8 AM are #242424, the working hours #292929, lines #5C5C5C (light unchanged). Other light-only calendar colours in dark (event fills, mini month week, #E0E0E0 lines) are follow-up TASK-0258.
- ost-fixV --version prints "ost-desktop 0.1.0" (the desktop crate's CARGO_PKG_VERSION; the 0.2.0 bump is the release's) and --help the usage; both exit 0 at once without opening a window or harness mode (run over ssh without a display).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Desktop fixes from the 0.2.0 release pass.

Changes:
- Calendar: the work week/day grid takes Teams' hosted-calendar palette in light and dark (calDay #FFFFFF/#292929, calOff #FAFAFA/#242424, calLine #D1D1D1/#5C5C5C, measured on winpc in both themes), so the hours before the working day are no longer white in dark theme.
- NOTICE.md describes the logo as it is (a wide OST plate in front of three people, gradient-shaded Fluent purples); make_logo.py's docstring names layout A as the default.
- ost-desktop --version / -V and --help / -h print the version (CARGO_PKG_VERSION) and usage and exit before anything starts; docs/desktop.md mentions them.

Tests: desktop crate tests on linuxlt; live: dark calendar screenshot, --version/--help on linuxlt.

Follow-up: TASK-0258 (the calendar's other dark colours).
<!-- SECTION:FINAL_SUMMARY:END -->
