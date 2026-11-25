---
id: TASK-0280
title: Debian/Ubuntu .deb package
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
OST ships only an AppImage and tarball. Offer a native .deb for Ubuntu/Debian that installs with apt (or a double-click) and uses the distro's own Qt, FFmpeg and webrtc-audio-processing where the versions allow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A .deb for ost-desktop and teams-cli builds reproducibly from the source and installs with apt on Ubuntu 26.04 (and current Debian testing if its libraries allow), pulling its dependencies
- [ ] #2 The installed app starts, signs in and has its menu entry, icon and the Bluetooth headset setup available, verified on linuxlt
- [ ] #3 Removing the package removes it cleanly
<!-- AC:END -->
