---
id: TASK-0284
title: 'Release CI: build every package on tag'
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
Releases should not depend on hand builds on linuxlt. A GitHub Actions workflow builds and attaches all packages when a version tag is pushed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pushing a vX.Y.Z tag builds the AppImage, tarball, .deb, .rpm and a Flatpak bundle in GitHub Actions and attaches them with SHA256SUMS to the GitHub release
- [ ] #2 The workflow also updates the AUR packages (and the Flathub manifest) to the new version
- [ ] #3 A test tag run on the fork succeeds end to end and the produced packages install on their distros
<!-- AC:END -->
