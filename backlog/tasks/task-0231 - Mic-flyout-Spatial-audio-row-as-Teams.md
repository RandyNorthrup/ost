---
id: TASK-0231
title: 'Mic flyout: Spatial audio row as Teams'
status: To Do
assignee: []
created_date: '2026-11-20T02:13:00Z'
updated_date: '2026-11-20T03:27:00Z'
labels:
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0181: Teams' in-call Mic flyout has a Spatial audio row above Noise suppression; OST's flyout doesn't.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST's Mic flyout shows the Spatial audio row exactly when and as Teams does, and it switches spatial audio
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 Teams (358966 SpatialAudioContainerInner; flyout 693727): the Mic flyout's effects section (Default flyout, not a template meeting, audio effects present) starts with SpatialAudioContainer at FLYOUT with shouldHideDescription and shouldHideInfoIcon: label "Spatial audio" and a switch, nothing else. Hidden only when spatial audio isn't available (feature on, desktop, slimcore version); off and disabled when the speaker isn't spatial capable or the call is P2P (or a meeting space group). Toggling calls setSpatialAudio (the device setting).
- Measured on winpc (DOM, flyout open in OST calendar test and in Teams' test call): 36 px row first in the effects section, label 14/20 #242424 at y 8.67 (18.67 box), switch track 40x20 at x 228 / y 8 (off: 0.67 #616161 ring, #616161 knob), Noise suppression's 36 px row directly below. Enabled in the test call too (not P2P). Gap from the microphone divider to the section: 10 (OST keeps its own 14.7 there: unchanged).
- Built: AudioFlyout Spatial audio row (capable from backend.spatialAudioCapable, setting spatialAudio, oneToOne = !meeting && !testCall; disabled look #E0E0E0 ring / #BDBDBD knob); switching sets spatialAudio, which renegotiates the meeting at once (TASK-0157). Harness: --vi-audio-ui logs VITEST spatial row; --vi-spatial-toggle switches it at 25 s and back at 40 s.

- Verified live (linuxlt): meeting OST calendar test (ost-test1 organizer, OST Test 2 + 3 admitted): row shown above Noise suppression, usable (Built-in Audio Analog Stereo is capable), switched on at 25 s (spatial audio: renegotiating, per_speaker=true taken) and off at 40 s (back to mixed). 1:1 call OST Test 2 -> OST Test 3: row shown off and disabled, the switch does nothing. OST test call (Echo): enabled, as Teams' test call. All calls left (202 / ended by the other side). 798 lib tests pass.
- Open: Teams' Audio settings pane also has the row (SETTINGS_PANEL, info button shown, no description); OST's pane doesn't yet. The flyout's gap from the microphone divider to the effects section is 10 in Teams with new meeting controls on (OST 14.7), not changed here.
<!-- SECTION:NOTES:END -->
