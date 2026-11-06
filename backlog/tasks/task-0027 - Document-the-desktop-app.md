---
id: TASK-0027
title: Document the desktop app
status: Done
assignee:
  - '@claude'
created_date: '2026-11-05T16:54:00Z'
updated_date: '2026-11-05T21:23:00Z'
labels:
  - desktop
  - docs
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The README covers the CLI and TUI only. The Qt desktop app (build, install, features, keyboard shortcuts, environment variables such as OST_SYSTEM_FRAME, OST_NO_KEYRING, OST_TROUTER_DUMP_DIR, the test harness flags and the Windows reference tooling) needs its own documentation before the upstream PR.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README has a desktop section covering build, install and run
- [x] #2 Environment variables and harness flags are listed with what they do
- [x] #3 Keyboard shortcuts match the app
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Documented the desktop app in docs/desktop.md, linked from a new README section.

Covers features and current gaps, build requirements (Arch and Debian packages), install with desktop/packaging/install-user.sh, sign-in, the files OST keeps, environment variables, keyboard shortcuts (matching the in-app Ctrl+. list) and all test harness flags.

The Windows reference tooling (VNC and CDP helpers) is local to the development machine and not in the repo, so it is not documented there.
<!-- SECTION:FINAL_SUMMARY:END -->
