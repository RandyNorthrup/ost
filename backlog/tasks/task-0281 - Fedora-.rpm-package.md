---
id: TASK-0281
title: Fedora .rpm package
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
