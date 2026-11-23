---
id: TASK-0256
title: Portable Linux release package
status: In Progress
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T16:07:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 0.2.0 tarball built on linuxlt (Ubuntu 26.04) needs its exact Qt 6.10, FFmpeg 8 and webrtc-audio-processing libraries, so it does not start on Arch (FFmpeg 9). The release needs a package that runs on current mainstream distros.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The release ships a self-contained package (AppImage or equivalent) bundling Qt, FFmpeg and webrtc-audio-processing
- [ ] #2 The package starts and signs in on both linuxlt (Ubuntu 26.04) and this Arch PC
- [ ] #3 README, the wiki Installation page and the release notes state which systems the package supports and how to build elsewhere
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Release-build ost-desktop and teams-cli on linuxlt (glibc 2.43 baseline).
2. AppImage with linuxdeploy + linuxdeploy-plugin-qt: QML modules found by qmlimportscanner over desktop/qml, Qt plugins (xcb, wayland, multimedia FFmpeg backend, imageformats, tls), QtWebEngine (process, resources, locales), FFmpeg and webrtc-audio-processing; leave the system to provide glibc, libstdc++, GL/Mesa, PipeWire/ALSA/D-Bus clients (their plugins and sockets are the system's).
3. AppRun/env so OST finds bundled Qt; QtWebEngine sandbox checked on both systems.
4. Run on linuxlt (profile test2) and on the Arch PC (own profile relU, OST Test 2 browser sign-in), then remove that profile.
5. README, wiki Installation and release notes updated.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23: started. The prebuilt tarball from linuxlt links libavcodec.so.62 (FFmpeg 8), Qt 6.10 and libwebrtc-audio-processing-1.so.3; Arch has FFmpeg 9 (libavcodec.so.63), so the tarball can't load there.
<!-- SECTION:NOTES:END -->
