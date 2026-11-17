---
id: TASK-0158
title: Automatically adjust camera controls as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T09:37:00Z'
updated_date: '2026-11-17T23:41:00Z'
labels:
  - devices
  - video
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Devices > Video settings > 'Automatically adjust camera controls' with 'Open camera settings' (Some settings might not be available for all camera types.): Teams lets the camera's own auto exposure / white balance / focus run, or opens the camera's settings. On Linux these are V4L2 controls.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Devices shows the switch, the 'Open camera settings' link and Teams' note
- [x] #2 The switch turns the camera's automatic controls on or off (V4L2), and the link opens OST's camera settings for the controls the camera offers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (settings-app `auto-camera-controls`, deviceManagerService): the switch calls the preview renderer's cameraAutoControl(enable) (the camera's own automatic exposure, white balance, focus, gain), kept on the device as automaticCameraSettingsSelected; unset, it shows what the camera reports. With the switch off, "Open camera settings" (ms-settings:camera?cameraId=… on Windows 11 with enableWindowsCameraSettingsLaunch, else slimcore openCameraSettings = the driver's property page) and "Some settings might not be available for all camera types.".
- winpc (2026-11-17, DOM + an element shot of the row only, never the preview): row 36 tall 30.7 under the camera dropdown; the link (14, brand) right under it with a 16 px Windows logo (osSettings variant), the note (12 on 17.1) under that, Green Screen 30 below. OST leaves the Windows logo out (no Microsoft branding; it opens OST's own settings).
- Built: calling::camera_controls (V4L2 by raw VIDIOC_QUERYCTRL/G_CTRL/S_CTRL on the standard ids: the v4l crate's enumeration panics on UVC's region-of-interest rect control); auto on/off (auto_exposure aperture priority/manual, white_balance_automatic, focus_automatic_continuous, gain_automatic, hue_auto; off keeps the values reached), applied whenever a camera opens; Settings row, link and note as Teams; CameraSettingsDialog (each control with Auto where it has one, Restore defaults).
- Verified live on linuxlt: --camera-controls-test on vivid (/dev/video2, screenshots t4/cam1-*.png): switch off → gain_automatic 0, Gain manual; Open camera settings lists Brightness/Contrast/Hue/Saturation/Gain(Auto); Brightness set 191 and back; switch on → gain_automatic 1. --camera-controls-test=/dev/video0 on the laptop's real camera (no page, no pictures): white_balance_automatic and auto_exposure off (manual 4600 K / 156) then back on; v4l2-ctl shows the camera exactly as before.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings > Devices > Automatically adjust camera controls works as in Teams.

Changes:
- The switch is kept on the device. With it off, "Open camera settings" and Teams' note appear, laid out as measured on winpc. The Windows logo on the link is left out on Linux.
- The switch drives V4L2 auto exposure, white balance, focus and gain.
- New OST camera settings dialog: sliders, Auto boxes and Restore defaults.
- Standard controls are queried directly, because the v4l crate crashed on extended controls.

Tests:
- Live on a vivid test camera: gain went manual, a slider took effect, and auto was restored.
- On the laptop camera, only control values were changed, with no images captured; it ended exactly as it started.
<!-- SECTION:FINAL_SUMMARY:END -->
