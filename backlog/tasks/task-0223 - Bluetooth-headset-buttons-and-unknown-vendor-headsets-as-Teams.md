---
id: TASK-0223
title: Bluetooth headset buttons and unknown-vendor headsets as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-18T04:41:00Z'
updated_date: '2026-11-23T05:28:00Z'
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
- [x] #2 An unknown-vendor USB headset whose UCQ string says it's a headset gets full call controls, as Teams
- [x] #3 'Transfer controls to this app' and Teams' transfer prompt work between two OST instances, verified live
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-19 (agent): built and verified live on linuxlt.
- Teams (bundle 89637, ms-teams.exe, Windows 11 BTAGService from Microsoft's symbol server): Bluetooth headsets go through Windows' HFP gateway and the VoIP call coordinator (HfpVoipCallCoordinatorImpl): reportIncomingCall rings the headset, ATA = AnswerRequested, AT+CHUP = Reject (ringing) / End, AT+VGM=0 mutes and a gain back above 0 unmutes (HfpAtVgmReceivedExpectMuteChange), Teams' mute sends +VGM: 0. Checks: Sync device buttons, selected mic Bluetooth, one BT hands-free device.
- OST: PipeWire's native HFP gateway takes ATA/AT+CHUP to a ModemManager modem; desktop/src/hfp_calls.rs offers OST's calls as one on the session bus (contrib/pipewire: bluez5 option bluez5.hfphsp-backend-native-modem-bus=session, a ~20-line patch, plus the WirePlumber setting). src/calling/hfp.rs watches the BT mic's volume (AT+VGM) and sets its route volume for OST's mute. Only the OST holding the headset buttons owns the name.
- UCQ: Teams reads USB string 0x21 (HidD_GetIndexedString(0x21) in SlimCoreWebview2.dll) and, with prod consolidateDrivers, any text there gives Standard Hook Protect USB. OST reads it with HIDIOCGSTRING on the hiddev node (usbfs fallback); Teams' prod driver table (blacklist, vendor groups, named PIDs), hook protection 1100 ms.
- Live: emulated HFP headset (btvirt pair + Bumble HF, ~/hf-emu.py): OST Test 2 rang, ATA answered, AT+VGM=0/15 muted/unmuted, AT+CHUP hung up, AT+CHUP while ringing rejected, Sync off refused (ERROR). Unknown-vendor gadget 16c0:0ab1 with UCQ at 0x21: HookProtect, hook 1 answered, mute toggled, hook 0 hung up; without string 0x21: MuteOnly. Transfer: spatest + default (same user): default showed Teams' prompt, Transfer controls moved the buttons (mute then acted on default's pre-join), Devices' Transfer controls to this app took them back.

- Merged e384d3c/aa012a8 (2026-11-18): build OK, 752 lib tests passed. AC2 and AC3 verified live. AC1: mute works on stock PipeWire; answer/hang-up need the contrib/pipewire patch (stock PipeWire's HFP gateway only talks to ModemManager on the system bus; org.pipewire.Telephony only covers the hands-free role). Patch being prepared for an upstream MR (user approved).
2026-11-19 (agent, follow-up): org.pipewire.Telephony checked: it only serves PipeWire as the hands-free side of a phone (README-Telephony.md; telephony_ag_new only in rfcomm_hfp_hf); live with the headset connected it lists no objects and ATA gets ERROR. Kept the modem path; contrib/pipewire now has an upstream-ready patch against PipeWire master (builds) with README. On stock PipeWire OST notices the gateway never reads its modem, logs that answer/hang-up aren't offered and shows nothing (Teams logs "Platform not supported" and shows nothing). Live on stock PipeWire: headset AT+VGM=0/15 muted/unmuted the call, AT+CHUP got ERROR (not offered), OST's own mute sent the headset +VGM: 0 and unmute +VGM: 15 (PipeWire forwards it once the headset has reported its gain, as real headsets do at connection). Harness --headset-mute-steps.

- Merged 203bc5a (2026-11-18): build OK, 752 lib tests passed. On stock PipeWire mute works both ways and answer/hang-up are not offered (Teams logs "Platform not supported" in the same case). Answer/hang-up with contrib/pipewire/0001-*.patch; upstream MR pending freedesktop.org fork approval (user filed the verification issue). AC1 stays open until the patch is upstream.

2026-11-22 (agent hfp1): stock-PipeWire path for AC1.
- Options: (1) ModemManager-shaped call provider on the system bus: PipeWire 1.6.2 modemmanager.c needs only WirePlumber's bluez5.hfphsp-backend-native-modem (default none; "ost" matches OST's Device) plus the name org.freedesktop.ModemManager1 on the system bus (GetManagedObjects without auto-start). Needs a D-Bus system policy for the user and ModemManager not running (it owns the name with no replacement and exits if it can't get it). (2) AVRCP/HID media keys: no ring, the headset sends no ATA without an AG call indicator, not what Teams does. (3) OST as HFP AG via BlueZ Profile1: PipeWire's HFP transport only comes from its own RFCOMM, so OST would have to run SCO audio itself; not workable. Chosen: (1).
- Feasibility with a Python mock on linuxlt: stock PipeWire rang the emulated headset, ATA -> Accept, AT+CHUP -> Hangup. NetworkManager, geoclue, kded6 and fwupd also call GetManagedObjects on that name, so OST now shows its modem only to its own user's WirePlumber/PipeWire (uid + process) and takes Accept/Hangup and the caller name only from it.
- Built: hfp_calls serves the system bus and the session bus (contrib patch); logs why it can't (no policy / ModemManager holds the name / WirePlumber not looking). desktop/packaging/install-hfp-calls.sh (+ ost-hfp-calls.dbus.conf, ost-hfp-calls.wireplumber.conf), --uninstall.
- Live (no call yet): OST Test 2 took the name on the system bus, stock PipeWire read its modem ("answer and hang-up are offered" bus=System); busctl as the user and as nobody, and mmcli, see no modems.

- Live on stock PipeWire 1.6.2 / WirePlumber 0.5.13 (linuxlt, ModemManager stopped, install-hfp-calls.sh): spatest (ost-test1) OST called OST Test 2 (emulated HFP headset as mic/speaker). Headset rang (RING, +CIEV callsetup 1); ATA -> "headset answered", call connected on both sides (+CIEV call 1); AT+VGM=0 / 15 muted/unmuted the call; AT+CHUP -> OK, call ended on both sides. Second call: AT+CHUP while ringing -> caller got RejectCall (603). During the ring, Accept from busctl as the user and as nobody was refused (AccessDenied) and nobody read Number "".
- First try failed Teams' check because micDevice held the node name; it holds the description ("OST HFP Headset (emulated)"), as Settings writes it. An unanswered ring goes to OST Test 2's voicemail after ~30 s.
- Restored on linuxlt: install-hfp-calls.sh --uninstall (policy and WirePlumber conf removed), ModemManager started again (it stayed enabled), rig down.
<!-- SECTION:NOTES:END -->
