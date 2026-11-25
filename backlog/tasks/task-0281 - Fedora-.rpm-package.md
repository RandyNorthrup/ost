---
id: TASK-0281
title: Fedora .rpm package
status: Done
assignee: []
created_date: '2026-11-25T01:16:00Z'
updated_date: '2026-11-25T06:02:00Z'
labels:
  - packaging
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Offer a native .rpm for Fedora (and openSUSE if feasible) using the distro's own Qt and libraries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An .rpm for ost-desktop and teams-cli builds from the source in a Fedora container and installs with dnf, pulling its dependencies
- [x] #2 The installed app starts on Fedora (container or VM with a display) and reaches Microsoft's sign-in page
- [x] #3 Removing the package removes it cleanly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- desktop/packaging/rpm/ost-desktop.spec and build-rpm.sh (dnf builddep or zypper) build ost-desktop and teams-cli for Fedora 45 (.fc45) and openSUSE Tumbleweed (.suse.tw) with the distribution's own Rust, Qt and FFmpeg.
- Requires: the shared libraries are found automatically; the Qt QML module and plugin packages are listed for each distribution.
- desktop/build.rs adds pkg-config's FFmpeg include path, because Fedora and openSUSE keep the headers in /usr/include/ffmpeg. Like the .deb, the build uses lld and no LTO.
- Verified with CI artifacts:
  - Clean fedora container: dnf install pulled the dependencies, OST showed Microsoft's sign-in page (Xvfb screenshot), and dnf remove left no files.
  - openSUSE: zypper installs the package (367 dependencies) and removes it cleanly. OST loads login.microsoftonline.com (CDP: "Sign in to your account"), but Qt WebEngine doesn't paint in a headless openSUSE container, so I have no picture of the page.
- Fedora's and openSUSE's FFmpeg leave out some patented codecs; the docs point to RPM Fusion and Packman.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Native .rpm packages for Fedora 45 and openSUSE Tumbleweed: ost-desktop and teams-cli, built against each distribution's own Rust, Qt 6, FFmpeg and libraries.

Changes:
- desktop/packaging/rpm/ost-desktop.spec and desktop/packaging/build-rpm.sh. `--deps` uses dnf builddep, or zypper with the spec's BuildRequires; the script sets the version and a %changelog entry. Packages are tagged .fc45 or .suse.tw.
- Requires: the shared libraries are found automatically by RPM. The Qt QML module, Wayland, SVG and image-format packages are listed per distribution.
- Recommends: PipeWire, WirePlumber, the portal, a keyring and layer-shell-qt.
- desktop/build.rs adds pkg-config's FFmpeg include path, because Fedora and openSUSE keep the headers in /usr/include/ffmpeg.
- Like the .deb: lld and no LTO.

Tests:
- Clean Fedora container: dnf install pulled the dependencies, OST showed Microsoft's sign-in page (Xvfb), and dnf remove left no files.
- openSUSE: zypper install pulled 367 dependencies, and removal is clean. OST loads login.microsoftonline.com (seen through CDP), but Qt WebEngine doesn't paint in a headless openSUSE container, so the page itself wasn't seen.

Follow-up:
- A check on a real openSUSE desktop.
- Fedora's and openSUSE's FFmpeg lack some patented codecs; the docs point to RPM Fusion and Packman.
<!-- SECTION:FINAL_SUMMARY:END -->
