---
id: TASK-0181
title: Voice isolation as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-19T15:45:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' noise suppression offers Voice isolation using your voice profile; OST shows it disabled though it can now enrol voice profiles (TASK-0153).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With a voice profile, Voice isolation can be chosen and keeps only your voice in calls
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 research (358966 re, 527114 device manager, RTMPLTFM.dll):
  - Teams' Voice isolation is "PNS": slimcore runs a downloaded proprietary "personalized DeepVQE" model (FPIE), conditioned on the voice profile's PNS signature (float32, from GET {biometric}/voice/pns/signature).
  - The choice is device-local: noiseSuppressionMode "Pns" = Voice isolation, "Auto" = Background noise only. Unset means Pns when a profile exists.
  - The Voice isolation radio is disabled without a voice profile; room audio forces Background noise only.
  - Linux has no slimcore PNS support, so OST needs its own model.
- Built:
  - ost_vfx::voice_isolation: CAM++ VoxCeleb speaker model (3D-Speaker, Apache-2.0, via tract), a Kaldi fbank in Rust, and an Isolator that gates other voices to -60 dB on a worker thread.
    - Measured: owner 0.86-0.89 vs other 0.10 cosine; suppression -50 dB per frame on the other voice; onset leak about 0.6 s; about 148 ms per 1.5 s embedding (release).
  - calling::voice_isolation: profile from the Recognition voice export (the enrollment WAV in the zip); it runs after APM in the capture path.
  - backend load_voice_isolation / apply_voice_isolation / voice_isolation_stats; Devices and the test call devices radios; OST_MIC_DEVICE env for tests.

- Status 2026-11-19:
  - Verified: ost-test1 voice profile enrolled (Piper lessac, scratch on linuxlt ~/set-research/enroll16.wav) with examples/biometric voice-enroll --store. The voice export is a zip holding exactly the enrollment WAV (…_VoiceRecording.wav).
  - Built: OST_DUMP_MIC (rebuild pending) for in-call checks.
  - Test rig on linuxlt:
    - PipeWire virtual source "ost_vi_mic" (pactl module 536870918; unload after).
    - OST_MIC_DEVICE="ost_vi_mic Audio/Source/Virtual sink".
    - ~/set-research/vi-ab.wav: A=lessac, B=ryan, segments A1 1.00-5.37, B1 6.37-9.75, A2 10.75-15.01, B2 16.01-19.26 s.
    - ~/set-research/vianalyze.py dump.raw vi-ab.wav.
  - Open: the in-call run (Make a test call) with Voice isolation on vs off; then remove the voice profile (examples/biometric remove-voice) and unload the source. The in-call Mic flyout and Audio settings pane radios are not added (their geometry is not measured).

- 2026-11-19 live check: a Make a test call run (--test-call-test) with ost-test1's voice profile.
  - The profile embedding loaded from the export, and Voice isolation was on by default (mode Pns, as Teams: unset means Pns with a profile).
  - The isolator ran in the call (IsolatorStats: decisions 79, frames_suppressed 960). The suppressed speech was the Echo bot's prompts that the built-in mic picked up.
  - OST_MIC_DEVICE didn't take: the call used Built-in Audio. The PipeWire null-sink source is probably dropped by audio.rs' "real device" filter (driver client-node), so the planned A/B check through the virtual mic is still open.
  - Afterwards: ost-test1's voice profile removed (status voice false) and the virtual source unloaded.

- 2026-11-19 model download (the model is no longer committed):
  - The CAM++ model is no longer in the repository or the binary. calling::voice_isolation::prepare downloads it on first need (a profile with Voice isolation chosen) from sherpa-onnx's speaker-recongition-models release to ~/.cache/ost/models/, checks its pinned SHA-256 (98daf9bc...88bb5; a cached file that doesn't match is removed and fetched again), writes it atomically (temp file, fsync, rename) and loads it. Until then calls get standard noise suppression (logged).
  - The profile is kept as its recording; its embedding is made once the model is loaded. OST_VOICE_PROFILE_WAV=<file> uses a local recording as the profile (tests).
  - vfx tests that need the model read OST_VOICE_ISOLATION_MODEL and skip without it.
  - Live on linuxlt (spatest, empty cache): download 5.4 s, hash verified, loaded, isolator on in a Make a test call run (decisions 10, frames_suppressed 101); a cached run verified; a corrupted cache file was replaced; an unwritable cache folder left standard noise suppression, no crash.

- Merged c4696d0 (2026-11-19) into desktop/foundation; 787 lib, 28 vfx, 29 desktop tests passed. See the notes above for what is verified and open. (Voice isolation model is downloaded on first need with a pinned SHA-256, not committed.)
<!-- SECTION:NOTES:END -->
