---
id: TASK-0223
title: Bluetooth headset buttons and unknown-vendor headsets as Teams
status: To Do
assignee: []
created_date: '2026-11-18T04:41:00Z'
updated_date: '2026-11-19T02:20:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0156 left: Bluetooth (HFP) headset call buttons aren't handled; a headset from a vendor Teams doesn't list only gets mute unless its USB UCQ string is read, which needs access to /dev/bus/usb; the 'Transfer controls to this app' button and prompt weren't clicked through live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Bluetooth headset's answer, hang-up and mute buttons control OST's calls as in Teams, verified live
- [ ] #2 An unknown-vendor USB headset whose UCQ string says it's a headset gets full call controls, as Teams
- [ ] #3 'Transfer controls to this app' and Teams' transfer prompt work between two OST instances, verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-19 (agent): built and verified live on linuxlt.
- Teams (bundle 89637, ms-teams.exe, Windows 11 BTAGService from Microsoft's symbol server): Bluetooth headsets go through Windows' HFP gateway and the VoIP call coordinator (HfpVoipCallCoordinatorImpl): reportIncomingCall rings the headset, ATA = AnswerRequested, AT+CHUP = Reject (ringing) / End, AT+VGM=0 mutes and a gain back above 0 unmutes (HfpAtVgmReceivedExpectMuteChange), Teams' mute sends +VGM: 0. Checks: Sync device buttons, selected mic Bluetooth, one BT hands-free device.
- OST: PipeWire's native HFP gateway takes ATA/AT+CHUP to a ModemManager modem; desktop/src/hfp_calls.rs offers OST's calls as one on the session bus (contrib/pipewire: bluez5 option bluez5.hfphsp-backend-native-modem-bus=session, a ~20-line patch, plus the WirePlumber setting). src/calling/hfp.rs watches the BT mic's volume (AT+VGM) and sets its route volume for OST's mute. Only the OST holding the headset buttons owns the name.
- UCQ: Teams reads USB string 0x21 (HidD_GetIndexedString(0x21) in SlimCoreWebview2.dll) and, with prod consolidateDrivers, any text there gives Standard Hook Protect USB. OST reads it with HIDIOCGSTRING on the hiddev node (usbfs fallback); Teams' prod driver table (blacklist, vendor groups, named PIDs), hook protection 1100 ms.
- Live: emulated HFP headset (btvirt pair + Bumble HF, ~/hf-emu.py): OST Test 2 rang, ATA answered, AT+VGM=0/15 muted/unmuted, AT+CHUP hung up, AT+CHUP while ringing rejected, Sync off refused (ERROR). Unknown-vendor gadget 16c0:0ab1 with UCQ at 0x21: HookProtect, hook 1 answered, mute toggled, hook 0 hung up; without string 0x21: MuteOnly. Transfer: spatest + default (same user): default showed Teams' prompt, Transfer controls moved the buttons (mute then acted on default's pre-join), Devices' Transfer controls to this app took them back.
<!-- SECTION:NOTES:END -->
