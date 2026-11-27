---
id: TASK-0316
title: 'Security: pinned, verified release toolchain and provenance'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-27T12:51:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The AppImage build runs tools from mutable releases without verifying a signature or hash; the Flatpak job runs a generator fetched from a moving branch and installs unpinned Python dependencies; checksums alone don't establish provenance.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every tool the release and CI workflows download is pinned to an exact version and verified by SHA-256 (or signature) before it runs; GitHub Actions are pinned to commit SHAs
- [x] #2 Python dependencies for build tools are pinned with hashes (pip --require-hashes)
- [x] #3 Releases publish GitHub build-provenance attestations (Sigstore) for every file, and the wiki explains how to verify them with gh attestation verify
- [x] #4 A test pre-release tag builds all packages successfully with the pinned toolchain
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Pin every workflow action in ci.yml/release.yml to a commit SHA (version comment); the Flatpak builder image by its sha256 reference
2. build-appimage.sh: linuxdeploy 1-alpha-20251107-1, appimagetool 1.9.1 and type2-runtime 20251108 by URL + SHA-256 (checked every run, --runtime-file); linuxdeploy-plugin-qt built from commit 9b9fca17 (its only release is too old) with its exclude list pinned by commit + SHA-256 and no build-time fetches
3. Flatpak job: flatpak-cargo-generator.py at commit 41c20aa1 + SHA-256; deps from a uv-compiled hashed requirements file (pip --require-hashes --only-binary :all:); Flathub signing key hash pinned
4. release job: actions/attest-build-provenance for every file (id-token/attestations write); workflow_dispatch dry run that builds everything and uploads release-files without attesting/publishing/AUR
5. Test the AppImage toolchain in an ubuntu:26.04 container on linuxlt; actionlint; document verification in SECURITY.md/README
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Actions pinned to commit SHAs (release.yml kept its majors: checkout v4.4.0, cache v4.3.0, upload-artifact v4.6.2, download-artifact v4.3.0 = what @v4 resolved to; CI already pinned). Flatpak builder image pinned by its sha256 reference. Distro images stay on tags (official images, signed distro repos, rolling distros) - stated in release.yml
- build-appimage.sh: linuxdeploy 1-alpha-20251107-1, appimagetool 1.9.1, type2-runtime 20251108 (now passed with --runtime-file; appimagetool would download the latest runtime), all SHA-256 checked on every run. linuxdeploy-plugin-qt has no usable release (1-alpha-20250213-1 lacks Wayland shell/networkinformation/Qt 6 AppRun changes), so it is built from commit 9b9fca17 (the current continuous build commit) with submodules at recorded commits, distro build deps, FETCHCONTENT_FULLY_DISCONNECTED, and its exclude list pinned (pkg2appimage 15a64c20 + SHA-256) instead of wget from master
- Tested on linuxlt in ubuntu:26.04: source-built plugin vs upstream continuous AppImage deploy the identical 1302-file AppDir for a Qt Quick test app; the real build-appimage.sh (OST deps, a stand-in binary) produced a 92 MB AppImage with all plugins and $ORIGIN RUNPATHs; second run re-verifies cached tools; a tampered appimagetool is refused
- Flatpak job: generator at flatpak-builder-tools 41c20aa1 + SHA-256; deps from cargo-generator-requirements.txt (uv --universal --generate-hashes) installed with pip --require-hashes --only-binary :all: and python -I (the image sets PYTHONPATH to its own site-packages). Install tested on Python 3.13 and 3.14. Flathub signing key hash pinned before remote-add
- release job: actions/attest-build-provenance v4.2.2 on dist/* (id-token + attestations write); workflow_dispatch dry run (always on a branch) builds every package, uploads release-files, skips attestation/release/AUR
- actionlint 1.7.12 clean except two pre-existing shellcheck infos
- Open: AC #3 needs the wiki text (Installation: Verifying downloads); AC #4 needs a dry-run on main (gh workflow run release.yml --ref main)

- 2026-11-27 AC #3: v0.3.0 carries attestations, and the wiki's Installation page has "Verifying downloads" with the plain and the strict gh attestation verify commands (--signer-workflow RandyNorthrup/ost/.github/workflows/release.yml --source-ref refs/tags/vX.Y.Z --deny-self-hosted-runners) and the SHA256SUMS check; SECURITY.md has the same. Checked against the real release: the strict command on v0.3.0's SHA256SUMS exits 0; with --source-ref refs/tags/v0.2.1 it fails ("expected SourceRepositoryRef to be refs/tags/v0.2.1, got refs/tags/v0.3.0").
- AC #4: release dry run on main (gh workflow run release.yml --ref main), run 45990740483 on b1e719f3: version, ubuntu, debian, rpm fedora:45, rpm opensuse/tumbleweed, flatpak and release all succeeded; the release job skipped "Build-provenance attestations" and "Attach to the release", aur was skipped; artifacts uploaded (release-files 904 MB, flatpak 139 MB). The v0.3.0 tag build itself (run 45815741896) also built every package with the pinned toolchain and attested them. No tag or release was created.

- PR #40: CI (build/test, clippy, format, dependency audit, release-build harness check, CodeQL) all passed; Codex code and security review: no findings.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Releases are now built with a pinned, verified toolchain and carry Sigstore build-provenance attestations for every file.

Changes:
- GitHub Actions in ci.yml and release.yml pinned to commit SHAs; the Flatpak builder image pinned by digest.
- build-appimage.sh: linuxdeploy, appimagetool and the type2 runtime pinned by URL + SHA-256 and checked on every run (runtime passed with --runtime-file); linuxdeploy-plugin-qt built from an exact commit with its exclude list pinned, no build-time fetches.
- Flatpak job: flatpak-cargo-generator.py at an exact commit + SHA-256; its Python deps from a hashed requirements file (pip --require-hashes --only-binary :all:); Flathub's signing key hash pinned.
- release job: actions/attest-build-provenance on every file; a workflow_dispatch dry run builds every package and skips attestation, release and AUR.
- Docs: SECURITY.md "Verifying a download" and "How the releases are built"; wiki Installation "Verifying downloads" with the gh attestation verify commands (strict form with --signer-workflow and --source-ref) and SHA256SUMS.

Tests:
- AppImage toolchain in ubuntu:26.04 on linuxlt (identical AppDir to upstream's continuous plugin; tampered tool refused); actionlint.
- gh attestation verify (strict) on v0.3.0's SHA256SUMS passes; a wrong --source-ref fails.
- Release dry run on main (run 45990740483) built all packages; the v0.3.0 tag run built and attested them.
<!-- SECTION:FINAL_SUMMARY:END -->
