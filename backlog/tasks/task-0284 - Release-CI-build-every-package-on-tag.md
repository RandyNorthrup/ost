---
id: TASK-0284
title: 'Release CI: build every package on tag'
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
Releases should not depend on hand builds on linuxlt. A GitHub Actions workflow builds and attaches all packages when a version tag is pushed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pushing a vX.Y.Z tag builds the AppImage, tarball, .deb, .rpm and a Flatpak bundle in GitHub Actions and attaches them with SHA256SUMS to the GitHub release
- [x] #2 A test tag run on the fork succeeds end to end and the produced packages install on their distros
- [ ] #3 The workflow updates the AUR packages to the new version once the AUR_SSH_KEY secret is set (the Flathub part is dropped)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- .github/workflows/release.yml runs on a pushed vX.Y.Z tag; a vX.Y.Z-x tag makes a pre-release.
  - version: the tag's core must equal Cargo.toml and desktop/Cargo.toml.
  - ubuntu:26.04: .deb, then installs those .debs (their Depends are the Qt modules and plugins the AppImage bundles), the AppImage, the tarball (build-tarball.sh), and a check that the AppImage's Wayland plugins have an $ORIGIN RUNPATH.
  - debian:testing: .deb.
  - fedora:45 and opensuse/tumbleweed: .rpm.
  - flatpak (kde-6.11 container): regenerates cargo-sources.json from Cargo.lock, then flatpak-builder and build-bundle with --runtime-repo flathub.
  - release: renames "~" to "." (GitHub's asset naming), writes SHA256SUMS, and creates the release (or uploads to an existing one) with gh.
  - aur: update-aur.sh on archlinux:latest, skipped for pre-releases and when the AUR_SSH_KEY secret is unset. Flathub is out: its policy doesn't accept AI-made manifests or submissions.
- Test tag v0.2.1-ci-test, runs 45531606585 to 45552378021. Fixes along the way: lld + no GCC LTO; FFmpeg include path (Fedora/openSUSE); zypper's busybox conflict; the AppImage's SVG plugin; openSUSE's libQt6Svg6; asset names.
- Final run 45552378021 on main 6084bc2c: all jobs green, AUR skipped.
  - The pre-release had 12 assets, and sha256sum -c SHA256SUMS was OK for all 11 files.
  - The Flatpak bundle installed with flatpak install --user on linuxlt (ost-desktop 0.2.1).
  - .deb/.rpm installs were tested in clean containers and on linuxlt from the earlier runs' artifacts (see TASK-0280/0281).
  - Test releases and tags are deleted.
- AC #2 stays open: the AUR job can't run until the user has an AUR account and AUR_SSH_KEY is set (registration is closed).
- Before 0.2.1: add <release version="0.2.1" date="…"/> to the metainfo. flatpak list and software centers show its newest release, which is still 0.2.0.

2026-11-25: v0.2.1 released by this workflow (run 45566931360): 11 assets + SHA256SUMS, all checksums OK, Ubuntu .deb installs/removes in a clean container, AppImage reports 0.2.1. The AUR job skipped (no AUR_SSH_KEY): AUR registration is closed.
<!-- SECTION:NOTES:END -->
