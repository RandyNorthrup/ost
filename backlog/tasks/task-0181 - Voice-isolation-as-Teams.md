---
id: TASK-0181
title: Voice isolation as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T04:53:00Z'
updated_date: '2026-11-20T01:09:00Z'
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
- [x] #1 With a voice profile, Voice isolation can be chosen and keeps only your voice in calls
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

- 2026-11-19 (set2): Teams' in-call choice (358966 module 327752 `be`, FLYOUT and SETTINGS_PANEL): with voice isolation supported, the Noise suppression switch row loses its info icon and a Fluent RadioGroup follows: "Background noise only" / "Voice isolation"; both disabled with the switch off; Voice isolation also without a profile and with Room audio (forced back to Background noise only); info tooltips only in the panes. Built NoiseSuppressionChoice.qml in AudioFlyout and AudioSettingsPane (Fluent v9 radio geometry: 16 px indicator 8 in, label 32 in, 36 rows) - winpc measurement still to do (needs the user's OK for winpc GUI).
- Virtual mic: a pactl null-sink with media.class=Audio/Source gets no ports from wireplumber, and remap-sources have no factory so audio.rs filters them; OST_MIC_DEVICE / OST_SPEAKER_DEVICE (new) now also take a PipeWire node name for an unlisted device. Rig on linuxlt: null sink ost_set2_feed + remap-source ost_set2_mic (OST_MIC_DEVICE=ost_set2_mic), null sink ost_set2_spk (record its monitor). Harness --voice-isolation-test (--vi-off-at, --vi-on-at, --vi-announce, --vi-admit).

- 2026-11-19 live two-voice check, a real 1:1 call ost-test1 -> OST Test 2 on linuxlt (--call-person / --call-test --remote-hangup, both --voice-isolation-test):
  - ost-test1's mic = ost_set2_mic fed with vi-ab.wav looped (A lessac = the profile, OST_VOICE_PROFILE_WAV=enroll16.wav; B ryan); OST Test 2's speaker = null sink ost_set2_spk, recorded from its monitor (parecord), analysed with vianalyze.py.
  - Voice isolation on (mode Pns, isolator running): received A1/A2 -0.8..+0.4 dB (kept), B1/B2 -54..-60 dB after the first second (whole-segment -2..-5 dB: the ~0.6 s onset leak), over 3 loops.
  - Control, no profile (Background noise only): B1/B2 +0.1..+1.0 dB, passed.
  - Both calls ended from the caller (hung up 202 / call ended by the other side in both logs).

- 2026-11-19 the choice in a live meeting (linuxlt, OST_VOICE_PROFILE_WAV, --vi-audio-ui): Audio settings pane: Noise suppression switch (no info), Background noise only (i) / Voice isolation (i), Voice isolation picked; Mic flyout: the same radios without info buttons. Geometry is Fluent v9's; winpc measurement pending the user's OK.

- Merged cc5e866 (2026-11-19): see the agent notes above; 791 lib tests passed on linuxlt.
<!-- SECTION:NOTES:END -->
