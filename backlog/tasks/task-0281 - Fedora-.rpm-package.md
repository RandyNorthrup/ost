---
id: TASK-0281
title: Fedora .rpm package
status: In Progress
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T01:16:00Z'
labels:
  - packaging
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Offer a native .rpm for Fedora (and openSUSE if feasible) using the distro's own Qt and libraries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An .rpm for ost-desktop and teams-cli builds from the source in a Fedora container and installs with dnf, pulling its dependencies
- [ ] #2 The installed app starts on Fedora (container or VM with a display) and reaches Microsoft's sign-in page
- [ ] #3 Removing the package removes it cleanly
<!-- AC:END -->
