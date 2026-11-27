---
id: TASK-0317
title: 'Security: least-privilege Flatpak and documented system changes'
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
From a public code audit of OST 0.2.1 (posted on Reddit, 2026-11-25). The Flatpak asks for broad device access, network, Downloads and Secret Service. The optional Bluetooth calling setup changes system D-Bus policy and can disable ModemManager.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Flatpak drops --device=all in favor of the camera portal and the narrowest device access calls need, keeps only the permissions OST uses, and each one is justified in the manifest and the wiki
- [x] #2 The Bluetooth calling setup lists every system change before making it, asks separately before touching ModemManager, never disables it without consent, and --uninstall restores everything (tested on linuxlt)
- [x] #3 SECURITY.md and the wiki's Privacy and data page describe what OST stores, where tokens live, what network hosts it talks to, and these optional system changes
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

- 2026-11-27 AC #1: TASK-0307 has landed, so the manifest already had --device=dri with cameras through the Camera portal; headset HID buttons stay .deb/.rpm/AppImage-only (Flatpak has no hidraw/hiddev permission narrower than --device=all). Every finish-arg rechecked against the code: audio goes through PipeWire (cpal's PipeWire host, xdg-run/pipewire-0) and Qt Multimedia's PulseAudio output, so both stay. Added to the manifest and docs: what the KDE runtime adds by itself (kdeglobals:ro, org.kde.KGlobalSettings, org.kde.kconfig.notify, com.canonical.AppMenu.Registrar) and that --socket=pulseaudio also exposes /dev/snd, which OST doesn't open.
- Built the Flatpak on linuxlt from this branch (flatpak-builder from org.flatpak.Builder, KDE 6.11 + QtWebEngine BaseApp 6.11; build metadata: devices=dri only). Smoke test, installed --user from the local repo, virtual mic ost_secwrap_mic (null sink + remap source, OST_MIC_DEVICE) and a PipeWire-only synthetic camera (GStreamer videotestsrc -> pipewiresink, Video/Source, role Camera), camera permission preset with flatpak permission-set (what the portal's Allow stores):
  - Launch: window up, sign-in page; signed in as ost-test3 with ost-signin over CDP. Tokens went to the keyring as teams-tokens@io.github.RandyNorthrup.ost.
  - Sandbox /dev: core dri fd full null ptmx pts random shm snd std* tty udmabuf urandom zero; dri = card1, renderD128. No video*, hidraw* or bus/usb nodes.
  - Camera: log "camera portal: access granted"; PipeWire clients of the app have pipewire.access=portal, media_roles=Camera. Settings > Devices camera list = Integrated Camera, USB Video, OST test camera A, OST-secwrap-test-camera (exactly PipeWire's four Video/Source nodes, no raw nodes); preview showed the synthetic camera's bars (only the synthetic camera was ever opened).
  - Audio: microphone list from PipeWire (Built-in Audio Analog Stereo, USB Video Analog Stereo; virtual null-sink sources are filtered as before). Make a test call (Teams' echo bot): capture from ost_secwrap_mic (pactl source-output ost-desktop -> ost_secwrap_mic), playback started, ICE/DTLS up, camera sent in the call; results screen: speaker, camera, network connected (mic "didn't work" because the virtual mic is silent). Mic watcher logged no stream on alsa_input.*.
  - Cleanup: flatpak kill, keyring entry cleared, app uninstalled with --delete-data, local remote and camera permission removed, modules unloaded, gst and watcher stopped, ~/ost-build-secwrap* removed.
- AC #3: PRIVACY.md and the wiki's Privacy and data page reconciled. PRIVACY.md gained the hfp-calls state folder, "tokens in config.toml only with Stay signed in without a keyring", "Extended diagnostics data", X11 shared memory, /dev/snd and KDE runtime notes, "nothing is paired" for BlueZ. The wiki page gained the full host list (same as PRIVACY.md), a SECURITY.md link and the same Flatpak notes (wiki commit cc4a346). SECURITY.md covers token handling and links PRIVACY.md for storage, token location, hosts, Flatpak permissions and the HFP setup's system changes.

- PR #40: CI (build/test, clippy, format, dependency audit, release-build harness check, CodeQL) all passed; Codex code and security review: no findings.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The Flatpak now asks only for what OST uses, the optional Bluetooth call setup asks before every system change and undoes them all, and the docs say what OST stores, where tokens live and which hosts it talks to.

Changes:
- Flatpak manifest: --device=all dropped for --device=dri; cameras come through the Camera portal (TASK-0307). Every finish-arg has a comment saying what it is for, including what the KDE runtime adds by itself and the /dev/snd that --socket=pulseaudio brings. Headset HID buttons are .deb/.rpm/AppImage-only, since Flatpak has nothing narrower than --device=all for hidraw.
- install-hfp-calls.sh: lists every change first (--dry-run only lists), asks before making them, asks separately before ModemManager (or --disable-modemmanager; --yes doesn't imply it), never touches it with a modem, records prior state; --uninstall restores files, folders and ModemManager's enabled/active state.
- PRIVACY.md rewritten from a code survey (hosts, token storage, storage table, log, Flatpak permissions, optional system changes); SECURITY.md links it; wiki Privacy and data matches it (hosts, storage, tokens, Flatpak permissions, optional system changes).

Tests:
- HFP setup install/uninstall paths on linuxlt with before/after snapshots (files, dirs, ModemManager state, bus name owner).
- Flatpak built on linuxlt and smoke-tested with ost-test3, a synthetic PipeWire camera and a virtual mic: launch and sign-in; sandbox /dev has only dri (+ snd); camera list via the portal shows exactly PipeWire's cameras and previews the synthetic one; microphone list from PipeWire; an echo test call recorded from the virtual mic and sent the camera.

Not covered: headset HID buttons inside the Flatpak (unavailable by design).
<!-- SECTION:FINAL_SUMMARY:END -->
