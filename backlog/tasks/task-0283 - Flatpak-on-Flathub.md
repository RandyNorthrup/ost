---
id: TASK-0283
title: Flatpak on Flathub
status: In Progress
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T05:00:00Z'
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
- [x] #1 A Flatpak manifest (KDE runtime) builds OST with flatpak-builder and the app runs sandboxed with working sign-in, notifications, audio, camera, screen sharing (portals) and the keyring
- [ ] #2 The app passes Flathub's linter (flatpak-builder-lint) with an AppStream metainfo, icon and desktop file
- [ ] #3 A .flatpak bundle is attached to each release and installs with `flatpak install`
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Flathub submission dropped (2026-11-24): Flathub's requirements page, "Generative AI policy", says "Flathub manifests must not contain AI-generated or AI-assisted content. Disclosure does not exempt manifests from this restriction." and "AI tools or agents must not open or automate Flathub submission pull requests, or generate their commit messages, descriptions, review comments, or replies." The same page asks for "a meaningful history of development". OST ships a self-hosted .flatpak bundle from its own in-repo manifest instead.

- Manifest desktop/packaging/flatpak/io.github.RandyNorthrup.ost.yml: KDE 6.11 runtime/SDK, io.qt.qtwebengine.BaseApp 6.11, rust-stable + llvm21 extensions, LayerShellQt 6.8.3 module, vendored crates in cargo-sources.json (regenerate from Cargo.lock; the release CI does). Source is the checkout (type: dir).
- Code it needed: d1824dcf (webrtc-audio-processing-2 fallback; the runtime has only -2), 320bd1db (build.rs links QtWebEngine via pkg-config when it is outside qmake's prefix, as with the BaseApp), b87fed69 (the keyring account carries FLATPAK_ID: the sandbox's first sign-in had overwritten linuxlt's host default-profile entry; ost-test1 restored there via the web picker).
- Built with org.flatpak.Builder on linuxlt (needs --disable-rofiles-fuse when detached), bundled with build-bundle --runtime-repo=flathub (138 MB), installed with flatpak install --user, run on linuxlt's Plasma desktop as OST Test 3: fresh sign-in on Microsoft's page; tokens in the host keyring as teams-tokens@io.github.RandyNorthrup.ost (host entries untouched); echo test call connected with microphone, speaker, camera (V4L2 Integrated Camera) and network all reported Connected; solo Meet now with the camera on and a KWrite test window shared through the KDE ScreenCast portal picker, stopped, left; Teams-style banner with quick reply and sound for a message from OST Test 1; the NetworkManager work-location banner appeared. Then uninstalled with its data; its keyring entry and ~/.var/app folder removed.
- Lint: manifest clean. Repo lint: only appstream-external-screenshot-url and screenshots-not-mirrored, which concern Flathub's own screenshot CDN (flathub-build mirrors to dl.flathub.org/media) and cannot apply to a self-hosted bundle.
- Not available in the sandbox: Bluetooth headset answer/hang-up (needs to own ModemManager1 on the system bus) and start on login (Background portal not wired).
<!-- SECTION:NOTES:END -->
