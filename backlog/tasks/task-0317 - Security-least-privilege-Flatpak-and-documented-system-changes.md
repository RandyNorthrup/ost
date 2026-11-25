---
id: TASK-0317
title: 'Security: least-privilege Flatpak and documented system changes'
status: To Do
assignee: []
created_date: '2026-11-25T19:49:00Z'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The Flatpak asks for broad device access, network, Downloads and Secret Service. The optional Bluetooth calling setup changes system D-Bus policy and can disable ModemManager.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Flatpak drops --device=all in favor of the camera portal and the narrowest device access calls need, keeps only the permissions OST uses, and each one is justified in the manifest and the wiki
- [ ] #2 The Bluetooth calling setup lists every system change before making it, asks separately before touching ModemManager, never disables it without consent, and --uninstall restores everything (tested on linuxlt)
- [ ] #3 SECURITY.md and the wiki's Privacy and data page describe what OST stores, where tokens live, what network hosts it talks to, and these optional system changes
<!-- AC:END -->
