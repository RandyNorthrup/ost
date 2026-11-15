---
id: TASK-0159
title: Connected devices (Settings > Devices) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T09:37:00Z'
updated_date: '2026-11-15T20:59:00Z'
labels:
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Devices page ends with 'Connected devices': 'Manage your connected devices' (Manage devices) and 'Automatically activate meeting room mode when in a meeting' (Learn More), for Teams Rooms / bring-your-own-device rooms (BYOD push-to-room audio). Verifying it needs a Teams Room or BYOD room peripherals in the test tenant: needs a user decision before work starts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Devices shows the Connected devices card with Teams' texts
- [x] #2 Manage devices and meeting room mode work with a room as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15: user decided: "we will need to emulate the hardware".

- Teams measured on winpc: Connected devices card (204.9), Manage devices subpage ("Select a device to connect", Better Together paired phones), the pre-join Room audio picker (search box, sections, subtitles, Join disabled without a room).
- Teams' BYOD rule read from its bundles: USB speaker+mic composites are "Connected room devices"; a VID/PID on byodRoomDeviceVidPids is auto-picked (meeting room mode on) or only "(suggested)" (off); joining opens the shared display on a second screen and shows "Connected to a room device" (body the first 3 times).
- Hardware emulated on linuxlt: dummy_hcd built from the kernel source, a configfs USB gadget with Jabra's id 0b0e:3012 (HID telephony), and PipeWire speaker/mic nodes tagged with the same USB ids (~/byod-gadget.sh up|down|audio|audio-down).
- Verified live: OST found and picked the emulated Jabra, switched speaker/mic to it, joined a channel Meet now with its audio (log: Audio input/output device: Jabra…), showed the notice, left.
- Follow-ups: TASK-0161 (tenant Teams Rooms), TASK-0162 (Better Together phones). OST has no voice-isolation mode, so Teams' Pns→Auto switch on room audio has nothing to act on.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings ▸ Devices ▸ Connected devices and Teams' meeting room mode (bring-your-own-device rooms), as Teams.

Changes:
- Settings ▸ Devices: Teams' Connected devices card (measured, 204.9 tall). It has Manage devices and the "Automatically activate meeting room mode when in a meeting" switch, with Teams' text and an inline Learn More (SwitchRow gained `link`/`centred`). Manage devices opens Teams' "Select a device to connect" page.
- Engine `calling::room_devices`: connected room devices from PipeWire (each node and device is bound for its full properties: USB vendor/product ids, product name, form factor). Teams' composite rule (USB, speaker + mic, no headsets), Teams' bundled or ECS `byodRoomDeviceVidPids`, and Teams' pick/suggest rule including meeting room mode off. Matching camera via sysfs. Unit tests.
- Pre-join Room audio rebuilt from Teams' measurements: the editable "Search for a room" picker, the "Connected room devices" (USB plug) and "Other Suggestions" sections, "(suggested)" and "We've detected a room device.", the line under the picker, and Join disabled until a room is chosen. Picking a room device switches speaker, mic (and camera) to it. Audio choices fill the column as in Teams (41/44.7, 6 apart).
- In the call: Teams' "Connected to a room device" notice. Its explanation shows only the first three times (byodSdmUfdTriggerCount). The shared display opens maximized on a second screen without taking focus.
- Harness: --room-audio-test [--room-audio-join=<channel>] [--manage-devices]; example `room_devices`.

Tests:
- cargo test --lib (526 passed).
- Live on linuxlt with an emulated Jabra Speak 750 (USB gadget with id 0b0e:3012 plus PipeWire nodes): picked automatically, suggested only with meeting room mode off, the call used the device's speaker and mic, the notice was shown, and OST left the call.

Follow-ups: TASK-0161 (tenant Teams Rooms), TASK-0162 (Better Together phones).
<!-- SECTION:FINAL_SUMMARY:END -->
