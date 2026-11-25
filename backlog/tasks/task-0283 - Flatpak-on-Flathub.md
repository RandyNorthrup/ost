---
id: TASK-0283
title: Flatpak on Flathub
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
Offer OST as a Flatpak on Flathub so every distro can install it from its software centre.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Flatpak manifest (KDE runtime) builds OST with flatpak-builder and the app runs sandboxed with working sign-in, notifications, audio, camera, screen sharing (portals) and the keyring
- [ ] #2 The app passes Flathub's linter (flatpak-builder-lint) with an AppStream metainfo, icon and desktop file
- [ ] #3 A Flathub submission is opened from the user's GitHub account and its review feedback handled
<!-- AC:END -->
