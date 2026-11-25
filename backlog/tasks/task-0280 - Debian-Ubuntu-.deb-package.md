---
id: TASK-0280
title: Debian/Ubuntu .deb package
status: In Progress
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T05:15:00Z'
labels:
  - packaging
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST ships only an AppImage and tarball. Offer a native .deb for Ubuntu/Debian that installs with apt (or a double-click) and uses the distro's own Qt, FFmpeg and webrtc-audio-processing where the versions allow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A .deb for ost-desktop and teams-cli builds reproducibly from the source and installs with apt on Ubuntu 26.04 (and current Debian testing if its libraries allow), pulling its dependencies
- [x] #2 The installed app starts, signs in and has its menu entry, icon and the Bluetooth headset setup available, verified on linuxlt
- [x] #3 Removing the package removes it cleanly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- desktop/packaging/debian (control, rules, copyright) and build-deb.sh build the ost-desktop and teams-cli .debs with dpkg-buildpackage, using the distribution's own Rust, Qt 6, FFmpeg, PipeWire, OpenSSL and webrtc-audio-processing.
- Depends come from dpkg-shlibdeps, plus the QML modules and Qt plugins OST loads at run time. Recommends: PipeWire, WirePlumber, xdg-desktop-portal, a keyring, layer-shell-qt.
- The link needs lld (cxx-qt) and no GCC LTO: dpkg-buildflags' -flto leaves GCC LTO objects that lld can't read.
- Debian testing builds too (Qt 6.11, FFmpeg 9). Its package depends on qt6-*-private-abi, so it follows testing's Qt version.
- Verified with the artifacts of CI run 45546434994:
  - Clean ubuntu:26.04 and debian:testing containers: apt pulled 463 and 514 packages, OST showed Microsoft's sign-in page under Xvfb, and removal left no files.
  - linuxlt (Ubuntu 26.04, KDE Wayland): installed with apt and launched from the menu entry. Signed in as ost-test1 through the browser account picker, and chats loaded.
  - KWin reports the window's desktop file as io.github.RandyNorthrup.ost, and the taskbar shows the icon.
  - A dry run of /usr/share/ost-desktop/install-hfp-calls.sh finds its files.
  - apt remove left nothing behind.
<!-- SECTION:NOTES:END -->
