---
id: TASK-0341
title: 'Real HDMI capture card: camera checks, and cameras start in a mode they offer'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T20:47:00Z'
updated_date: '2026-11-26T23:15:00Z'
labels:
  - bug
  - calls
  - privacy
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
linuxlt now has a real non-loopback camera device, a MacroSilicon MS2109 USB HDMI capture card (534d:2109, UVC: Motion JPEG up to 1920x1080@60, YUYV at 5-30 fps). The camera work of TASK-0305/0307/0308/0321/0322/0338 was only checked with v4l2loopback devices. Checked live with the card: the camera list, preview, pre-join and meetings, a 1:1 call, the clip recorder, face capture's list, privacy tracing, the V4L2 fallback without PipeWire cameras, and the card removed and back. Found: the card's preview failed (PipeWire: error set output format -22) because OST asked for sizes and rates as ranges and PipeWire's V4L2 source fixated one the card doesn't offer (640x360 at 15 fps); the V4L2 path picked the format before the size and rate; Settings > Devices didn't follow cameras plugged in or removed and its preview didn't come back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A camera is captured in one of the modes it lists (format, size, rate), chosen as Chromium does, through PipeWire and through V4L2; the MS2109 card previews and sends video
- [x] #2 Settings > Devices' camera list follows cameras added or removed while it shows, and its preview comes back when the chosen camera returns (never another camera in its place)
- [x] #3 Live on linuxlt with the card: list, preview, pre-join + solo meeting, 1:1 call received by OST Test 2, clip recorder file, face capture list, privacy trace, V4L2 fallback without PipeWire cameras, removal via USB authorized; no footage saved
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Live checks with the card on linuxlt (main + PR #23, merged meanwhile): list, preview, pre-join/meeting, 1:1 call, recorder, face list, tracing, V4L2 fallback (WirePlumber camera monitors off), USB authorized 0/1.
2. Fix the preview failure: read the camera node's EnumFormat (PipeWire) / ENUM_FRAMESIZES+FRAMEINTERVALS (V4L2) and connect with exact modes ordered like Chromium (camera_mode.rs).
3. Settings > Devices: follow camera changes while shown; preview recovers when the chosen camera returns.
4. Harness: --recorder-camera=<name>, --face-camera-test, --devices-watch-test, backend.videoFrameStats (no pictures).
5. Unit tests, PR, CI + Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- PR #23 merged during the work (ac24fa04); branch rebased on main.
- Found live: the card's preview failed through PipeWire ("error set output format: -22"; spa.v4l2: "wanted YUYV 640x360, got YUYV 640x480"): OST's EnumFormat ranges (size 16x16-640x360 default 640x360, rate 0-120 default 15) were fixated by PipeWire's V4L2 source to a mode the card lacks. Loopbacks offer one fixed format, so this never showed.
- Fix: camera_mode.rs orders a camera's own modes like Chromium (smallest size covering the wanted one, else largest; lowest rate reaching the wanted one, else highest; cheaper format). camera_pw reads the node's EnumFormat over the capture's own connection and offers the 8 best modes as exact pods (ranges only when the node gives none in 1.5 s); the V4L2 path enumerates FRAMESIZES/FRAMEINTERVALS. Card: preview/call 640x480 YUYV@20 (77 modes), recorder 1280x720 MJPG@30.
- Settings > Devices: list re-read every 2 s while shown; preview reopened when the chosen camera returns; "opens" (chosen camera or "" while missing) drives the preview and its controls. Found in the USB authorized test: with the chosen camera missing, "current" fell back to the first camera and the auto-controls row opened that camera's node (/dev/video20) to read its state.
- Qt Multimedia once hung at startup in pw_thread_loop_lock (QMediaDevices::audioOutputs, QAudioOutput creation): unrelated to cameras; the retry ran fine.
- The card also offers an audio input (alsa_input.usb-MACROSILICON...): micguard treats it like the built-in mic; OST always recorded from ost_capture_mic.

- Live on linuxlt (card = pipewire:v4l2_input.pci-0000_00_14.0-usb-0_3_1.0 via OST_CAMERA_DEVICE; real camera chmod 000 during runs; virtual mic ost_capture_mic, no stream ever on alsa_input.*; no picture saved: shots pointed at a missing folder, frames checked by sequence/size/checksum, the recorder clip and its frame JPGs deleted unviewed after ffprobe):
  - List: Integrated Camera, USB Video, OST test camera A (+ C while another agent fed it); card once, by name, no /dev/video3.
  - Preview: 640x480 YUYV@20 (77 modes), self frames 480x360 ~20/s; the HDMI source picture is static (same checksum; GStreamer from the card: 90 frames, 1 distinct), so change can't be shown.
  - --prejoin-camera-test x2 rounds: all checks pass.
  - 1:1 ost-test1 -> OST Test 2: sender 480x360 at 600 kbps, 300 sent; receiver decoded 300 frames 480x360, remote video shown.
  - Recorder (--recorder-camera=USB~Video): 1280x720 MJPG@30; clip h264 1280x720, 12.05 s, 358 frames (~30 fps).
  - Face capture list: USB Video, Integrated Camera, OST test camera A; card opened while shown, closed after.
  - Tracing (may_open + v4l2_open + openat, fuser 0.1 s): OST itself opened only the card's capture node (controls read, V4L2 capture); idle 68 s: nothing.
  - No PipeWire cameras (WirePlumber monitor.v4l2/libcamera disabled, restored after; vivid n_devs=1 node_types=0x1 as a node only opening describes): list Integrated Camera, USB Video, vivid, OST test camera A from sysfs/udev; opens: card x2, vivid x1 (asked once while the list showed); preview 640x480 YUYV@20; --prejoin-camera-test passes, card x10 only.
  - USB authorized 0/1: list drops the card within 2 s, preview stops and waits ("isn't there"), list and preview back 2-3 s after authorize; only the card's nodes opened (before and after renumbering).
<!-- SECTION:NOTES:END -->
