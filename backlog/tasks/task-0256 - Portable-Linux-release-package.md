---
id: TASK-0256
title: Portable Linux release package
status: In Progress
assignee: []
created_date: '2026-11-23T15:54:00Z'
updated_date: '2026-11-23T15:54:00Z'
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
