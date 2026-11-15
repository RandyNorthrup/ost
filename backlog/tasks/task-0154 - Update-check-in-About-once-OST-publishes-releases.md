---
id: TASK-0154
title: Update check in About, once OST publishes releases
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T06:09:00Z'
updated_date: '2026-11-15T19:44:00Z'
labels:
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > About shows 'You've got the latest version. It was last checked on <date>.' (or an update). OST has no release channel yet (no GitHub releases), so About shows only the version. Needs a user decision on how OST is released before it can be built.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 About shows Teams' update line from OST's release channel: up to date with the last check date, or a newer version with how to get it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15: user authorized setting up whatever is needed; OST's release channel is GitHub Releases on RandyNorthrup/ost.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
About OST shows Teams' update line from OST's release channel.

- Release channel: GitHub Releases on RandyNorthrup/ost; OST 0.1.0 published (tag v0.1.0 on desktop/foundation) with build notes.
- api::updates: the latest release (GitHub API) and version comparison (tests).
- The desktop checks soon after start and daily (and on About's harness); the last successful check is kept on the device.
- About OST: "Checking for updates", "You've got the latest version. It was last checked on <short date>.", "An update is available." with Teams' Update now (opens the release), or "Issue occurred while checking for updates." — Teams' strings and logic (settings-app `vd`).

Tests: api::updates unit tests; --about-test on linuxlt (real check → latest; available state with Update now).
<!-- SECTION:FINAL_SUMMARY:END -->
