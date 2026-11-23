---
id: TASK-0256
title: Portable Linux release package
status: In Progress
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T17:40:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 0.2.0 tarball built on linuxlt (Ubuntu 26.04) needs its exact Qt 6.10, FFmpeg 8 and webrtc-audio-processing libraries, so it does not start on Arch (FFmpeg 9). The release needs a package that runs on current mainstream distros.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The release ships a self-contained package (AppImage or equivalent) bundling Qt, FFmpeg and webrtc-audio-processing
- [x] #2 The package starts and signs in on both linuxlt (Ubuntu 26.04) and this Arch PC
- [x] #3 README, the wiki Installation page and the release notes state which systems the package supports and how to build elsewhere
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

- AppImage built on linuxlt with linuxdeploy + linuxdeploy-plugin-qt + appimagetool (script: build-appimage.sh, kept with the release tooling): Qt 6.10 with QML modules, platform plugins (wayland, xcb), Wayland EGL/shell/decoration plugins, LayerShellQt, multimedia (FFmpeg backend), tls, image formats; QtWebEngine (process, resources, locales); FFmpeg 8 and webrtc-audio-processing bundled. Left to the system: glibc, libstdc++/libgcc_s, GL/EGL/gbm/drm/vulkan, PipeWire/ALSA/PulseAudio clients, D-Bus, systemd, Wayland client libs, OpenSSL. AppRun also runs teams-cli (first argument teams-cli, or linked as teams-cli). OST-0.2.0-x86_64.AppImage: 292 MB.
- linuxlt (Ubuntu 26.04, KDE Wayland), profile spatest: starts, loads Qt/FFmpeg/webrtc from the AppImage mount (checked in /proc/<pid>/maps), QtWebEngine processes run, the browser sign-in renews ("browser sign-in renewed"), calendar loads. teams-cli --help through the AppImage works.

- Arch PC (Arch Linux, glibc 2.44, FFmpeg 9, Qt 6.11 installed, Hyprland Wayland): the same AppImage (sha256 22ee68bf…) starts with Qt 6.10, FFmpeg 8 and webrtc-audio-processing from the AppImage (checked in /proc/<pid>/maps; system libstdc++, EGL/Mesa, PipeWire and OpenSSL), Wayland EGL plugin loaded. New profile relU: Microsoft's sign-in page in OST's window, signed in as OST Test 2 (password typed from creds.md through CDP, never printed; no MFA asked), "browser sign-in complete", Trouter connected, chat list shown. teams-cli --help through the AppImage works. Profile relU removed afterwards (profile folder, keyring entry teams-tokens:relU, accounts.json, its log); the shared web profile ost-apps on this PC still holds a Microsoft web session for OST Test 2.

- Packaging script committed as desktop/packaging/build-appimage.sh (relU branch e6cf376c; downloads linuxdeploy, its Qt plugin and appimagetool on first use); a run of it on linuxlt produced the same AppDir file set and size as the tested AppImage.
- The AppImage runtime mounts with FUSE 3 (fusermount3); no libfuse2 needed (Arch PC has only fuse3).
- README (Install, Build, Terminal client), wiki Installation / Building-from-source / FAQ / Troubleshooting / Terminal-client, and the 0.2.0 release-notes draft now describe the AppImage, the supported systems (x86-64, glibc 2.43+, tested Ubuntu 26.04 and Arch) and building elsewhere.
<!-- SECTION:NOTES:END -->
