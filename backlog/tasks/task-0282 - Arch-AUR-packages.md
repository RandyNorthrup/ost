---
id: TASK-0282
title: Arch AUR packages
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
Offer OST on the Arch User Repository: ost-bin (from the release AppImage/tarball) and ost (built from source against Arch's Qt and libraries).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PKGBUILDs and .SRCINFO for ost-bin and ost build and install with makepkg on current Arch, and namcap is clean
- [ ] #2 The installed app starts and signs in on Arch (this PC for ost-bin; a clean Arch build environment for ost)
- [ ] #3 Both packages are published on the AUR under an account owned by the user
<!-- AC:END -->
