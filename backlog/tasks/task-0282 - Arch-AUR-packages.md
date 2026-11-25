---
id: TASK-0282
title: Arch AUR packages
status: In Progress
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T08:12:00Z'
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
- [x] #1 The installed app starts and signs in on Arch (this PC for ost-bin; a clean Arch build environment for ost)
- [ ] #2 Both packages are published on the AUR under an account owned by the user
- [x] #3 PKGBUILDs and .SRCINFO for ost-bin and ost build and install with makepkg on current Arch; namcap is clean on both PKGBUILDs and on the ost package, and ost-bin's remaining warnings are only about libraries and QML bundled inside the AppImage
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- PKGBUILDs: desktop/packaging/aur/ost (source tag, Arch Qt/FFmpeg/webrtc-audio-processing-1) and desktop/packaging/aur/ost-bin (release AppImage unpacked to /usr/lib/ost, symlinks in /usr/bin). Both target 0.2.1; CI (desktop/packaging/update-aur.sh) sets pkgver/sums and pushes.
- ost-bin verified on this Arch PC with the 0.2.0 AppImage: makepkg, pacman -U, OST started signed in (OST Test 1, chats loaded), pacman -Rns clean.
- ost built in a clean archlinux:latest container on linuxlt (Qt 6.12.0, FFmpeg 9.1, rust 1.100): no source changes needed. Needed options=(!lto) (makepkg LTO makes the C++ objects GCC bitcode the Rust link cannot resolve). Installed in a fresh container, started on linuxlt's Wayland desktop, signed in fresh as OST Test 3 (chats loaded), removed.
- namcap: PKGBUILDs clean. ost package: only false positives left (compiled-in QML module com.ost.desktop, sh for the optional HFP script, ld-linux, qt6-svg/qt6-wayland which Qt loads as plugins). ost-bin: warnings and QML-module errors come from the bundled Ubuntu libraries and QML (namcap maps QML imports only to /usr/lib/qt6/qml), inherent to a bundled -bin.
- AUR account: registration closed (HTTP 503, temporarily closed, no date). SSH key ready at ~/.ssh/aur_ost; ~/.ssh/config has Host aur.archlinux.org.
<!-- SECTION:NOTES:END -->
