---
id: TASK-0156
title: Sync device buttons (headset call controls) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T09:37:00Z'
updated_date: '2026-11-18T04:41:00Z'
labels:
  - calling
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Devices > Audio settings > 'Sync device buttons' (This lets you use all the buttons on your device. The Teams button will...): Teams handles a USB/Bluetooth headset's call buttons (answer, hang up, mute, Teams button) over HID telephony. OST doesn't read headset buttons yet; on Linux they arrive through hidraw / the HID telephony usage page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Devices shows 'Sync device buttons' with Teams' text, kept as Teams keeps it
- [x] #2 With it on, a headset's answer, hang-up and mute buttons control OST's calls, and OST's mute state shows on the headset, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-17 (agent): built and verified live on linuxlt with an emulated USB headset.
- Teams (bundles 89637/settings-app; winpc 2026-11-17): Settings > Devices shows 'Audio device button controls' (Transfer controls to this app: Teams' HID2 control between its apps) and 'Sync audio device buttons when in use on this app' (audioDeviceSyncEnabled in local storage, default on; off: call-control reports ignored and no LEDs set, the Teams button still works). Drivers: known vendors or a UCQ string -> 'Standard Hook Protect USB' (hook switch, flash, mute, Button 7 reject, 1 s hook protection); others 'Safe Mute Only'. LEDs: Off-Hook while a call is up, Ring while ringing, Mute, Hold. Teams button = page 0xFF99 usage 4 + ASP feature report 0x9A (Version, Feature, Context; short press: missed call -> Calls, else bring Teams and the meeting forward; long press in a meeting: raise hand).
- OST: calling::hid_telephony (hidraw + sysfs report descriptor parser, Teams' drivers, LEDs, ASP, control between OST instances via XDG_RUNTIME_DIR/ost-hid-control with Teams' transfer prompt), backend headset_* invokables and signals, Settings rows, Main.qml wiring, harness --headset-test[=prejoin].
- Rig: ~/byod-gadget.sh headset / headset-audio (0b0e:2400 Jabra-style descriptor, udev uaccess rule, ~/hs-emu.py device side, buttons via /tmp/hs-cmd).
- Live (OST Test 2 calling ost-test1): Ring LED while ringing; hook 1 answered; mute/unmute toggled the call and the Mute LED; hook 0 hung up, LEDs off, caller ended. Reject button declined. Sync off: hook and mute ignored, no LEDs. Missed call pushed to the device; the Teams button then opened Calls. Pre-join mute toggled the pre-join mic and LED. Long press raised the hand in a meeting (HTTP 200).
- Open: Bluetooth (HFP) headset buttons; reading the UCQ string needs write access to /dev/bus/usb (without it unknown vendors get mute only).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Headset call buttons and lights work as in Teams.

Changes:
- Settings > Devices: "Audio device button controls" with "Transfer controls to this app", and "Sync audio device buttons when in use on this app" (audioDeviceSyncEnabled, on by default, kept on the device).
- src/calling/hid_telephony.rs reads hidraw telephony usages with Teams' rules:
  - known vendors get hook, flash, mute and reject; others get mute only unless UCQ says headset;
  - off-hook answers and on-hook hangs up, with a 1 s guard;
  - Reject declines; Mute toggles the call or the pre-join mic.
- Lights: Off-Hook, Ring, Mute, Hold. Teams button: short press opens Calls after a missed call or brings OST forward; a long press in a meeting raises the hand.
- Arbitration between OST instances, with Teams' transfer prompt. Harness --headset-test.
- Rig: an emulated Jabra telephony headset on linuxlt (~/byod-gadget.sh headset, ~/hs-emu.py).

Tests:
- 723 lib tests.
- Live with OST Test 2 calling ost-test1: ring light; off-hook answers; mute and light; on-hook hangs up; reject declines; Sync off ignores the buttons; Teams button after a missed call; pre-join mute; long-press raise hand.

Follow-up: TASK-0223 (Bluetooth, UCQ, transfer prompt live).
<!-- SECTION:FINAL_SUMMARY:END -->
