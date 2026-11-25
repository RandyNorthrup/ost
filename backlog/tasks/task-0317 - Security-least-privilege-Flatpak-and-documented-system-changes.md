---
id: TASK-0317
title: 'Security: least-privilege Flatpak and documented system changes'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T19:49:00Z'
updated_date: '2026-11-25T20:27:00Z'
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
- [x] #2 The Bluetooth calling setup lists every system change before making it, asks separately before touching ModemManager, never disables it without consent, and --uninstall restores everything (tested on linuxlt)
- [ ] #3 SECURITY.md and the wiki's Privacy and data page describe what OST stores, where tokens live, what network hosts it talks to, and these optional system changes
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Flatpak finish-args: justify each permission against the code; keep --device=all with TODO(TASK-0307) since TASK-0307 has not merged (headset HID needs it regardless: no Flatpak hidraw permission)
2. install-hfp-calls.sh: list all changes first (--dry-run), confirm, separate ModemManager consent (prompt or --disable-modemmanager; --yes no longer implies it), record prior state (MM enablement/activity, replaced files, created dirs) and restore it on --uninstall
3. Test install/uninstall paths on linuxlt with before/after snapshots
4. PRIVACY.md/SECURITY.md: storage, tokens, hosts, Flatpak permissions, optional system changes
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Flatpak finish-args: every permission justified against the code (comments in the manifest). Nothing could be dropped: each is used. --device=all kept with TODO(TASK-0307): TASK-0307 (cameras via PipeWire/camera portal) has not merged into main. Also found: headsets' call buttons use hidraw/hiddev/usbfs (src/calling/hid_telephony.rs) and Flatpak has no narrower permission for hidraw/hiddev (--device=input = /dev/input, --device=usb = /dev/bus/usb), so after TASK-0307 --device=all still stays for headset HID unless headset buttons are left out of the Flatpak (then --device=dri). AC #1 needs that decision
- install-hfp-calls.sh rewritten: lists every change first (create/update/replace/keep per file), --dry-run, asks "Make changes 1-3?" (or --yes); ModemManager is a separate question (or --disable-modemmanager); --yes no longer disables it; never touched with a modem. State in ~/.local/share/ost/hfp-calls/: ModemManager's prior is-enabled/is-active, backups of replaced non-OST files, folders it created. --uninstall lists and restores all of it (also honours the old state file)
- Tested on linuxlt (ModemManager enabled+active, no modem; ~/.config/wireplumber empty): dry run and non-tty refusal change nothing; --yes leaves ModemManager running; interactive y/y disables it (name unowned), uninstall re-enables and starts it; a pre-existing user file is backed up and restored; all four runs back to the exact before-snapshot (files, dirs, ModemManager state, name owner, WirePlumber active)

- PRIVACY.md rewritten from a code survey (paths confirmed on linuxlt): hosts incl. the daily update check to api.gh, Giphy media, Hugging Face and gh-hosted models; token storage (keyring service ost, config.toml 0600 fallback, web-profile cookies); sign-out leaves web profile/caches/log (TASK-0313 covers clearing); full storage table; unmasked log + Collect Support Files; Flatpak permissions; HFP changes. SECURITY.md points to it. Wiki Privacy and data page still to update (AC #3)
<!-- SECTION:NOTES:END -->
