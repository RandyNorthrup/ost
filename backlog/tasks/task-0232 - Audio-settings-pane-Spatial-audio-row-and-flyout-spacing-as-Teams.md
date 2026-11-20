---
id: TASK-0232
title: 'Audio settings pane: Spatial audio row and flyout spacing as Teams'
status: To Do
assignee: []
created_date: '2026-11-20T03:37:00Z'
updated_date: '2026-11-20T04:08:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0231: Teams' in-call Audio settings pane also has the Spatial audio row; OST's pane doesn't. In the Mic flyout, the gap from the Microphone divider to the effects section is 10 px in Teams (new meeting controls on) and 14.7 px in OST.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Audio settings pane shows the Spatial audio row as Teams does and it switches spatial audio
- [ ] #2 The Mic flyout's effects section spacing matches Teams' measurements
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 (agent c3) Teams (audio-settings-panel 311594): Advanced settings = [SpatialAudioContainer at SETTINGS_PANEL (shouldHideDescription, info shown, AVF), noise suppression, music mode]. Info text calling_spatial_audio_title_tooltip_avf ("Enable this to experience audio ... <0>Learn more</0>", link spatialAudioLearnMoreLink). Disabled/off when not spatial capable or P2P (358966 pe).
- Flyout (693727 O): the microphone section has microphoneSelection padding-top 4px (that is the 14.7 under the speaker divider); the effects section has no padding (class only with enableUbarVisualRefresh, not set by New meeting controls), so the gap under the microphone divider is 10 as measured.
- Built: AudioSettingsPane Spatial audio row (SwitchRow with info + disabled look), CallWindow passes oneToOne; flyout gap 14.7 -> 10; harness --vi-spatial-pane (VITEST pane spatial row).
<!-- SECTION:NOTES:END -->
