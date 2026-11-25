---
id: TASK-0283
title: Flatpak on Flathub
status: In Progress
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T01:29:00Z'
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
- [ ] #3 A .flatpak bundle is attached to each release and installs with `flatpak install`
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Flathub submission dropped (2026-11-24): Flathub's requirements page, "Generative AI policy", says "Flathub manifests must not contain AI-generated or AI-assisted content. Disclosure does not exempt manifests from this restriction." and "AI tools or agents must not open or automate Flathub submission pull requests, or generate their commit messages, descriptions, review comments, or replies." The same page asks for "a meaningful history of development". OST ships a self-hosted .flatpak bundle from its own in-repo manifest instead.
<!-- SECTION:NOTES:END -->
