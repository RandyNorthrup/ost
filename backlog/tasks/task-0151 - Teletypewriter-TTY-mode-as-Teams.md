---
id: TASK-0151
title: Teletypewriter (TTY) mode as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T05:37:00Z'
updated_date: '2026-11-18T02:09:00Z'
labels:
  - calling
  - accessibility
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Accessibility > 'Teletypewriter (TTY) mode' (isTTYSettingEnabled / toggleTTYSetting): Teams' desktop media stack turns on TTY support (mediaConfigurationService.enableTtySupport) and keeps the choice on the device; after toggling, Teams shows its 'active call' notice (tty_dialog_active_call_warning). Find out exactly what TTY support changes in the media path (audio processing, codec) and do the same in OST's audio engine; the card is left out until then.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings > Accessibility shows 'Teletypewriter (TTY) mode' with Teams' text and icon, kept on this device, and the notice Teams shows after toggling
- [x] #2 With it on, OST's call audio is handled as Teams' TTY support handles it, so a TTY device's tones pass through a call intact (checked against Teams)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (settings-app, 89637 deviceManagerService, desktop media stack): the card is Settings ▸ Accessibility ▸ "Teletypewriter (TTY) mode" (Teams' accessibility glyph, desktop only via showTTYSettings). toggleTTYSetting → enableTTYSupport → mediaConfigurationService.enableTtySupport → setMediaConfig({enableTtySupport}); kept in local storage, loaded at start. After a change: info glyph + "Changes will be applied for your next call" (also announced).
- Native (Teams' RtmMediaManager.dll / RTMPLTFM.dll, read on linuxlt with strings + objdump): RtmMediaManager parses `enableTtySupport` into the media config; RTMPLTFM sets the audio channel's EnableTty (listed with EnableSilenceSuppression, comfort-noise generation and EnableReceiveAgc) and the audio engine setting TTyMode (_AESetting_e 8, AudioEngineSetSettingTTyMode). The engine's TTY processing itself runs in a remote audio engine with no log strings; OST does what that switch exists for: the TTY device's Baudot tones go out unprocessed.
- winpc (2026-11-17, DOM; TTY switched on and back off): card 93.3 tall, 129.3 with the notice; the notice's glyph 8 left of the text column, 16 under the subtitle, its text 10 after the glyph. OST matches.
- Built: the card (setting ttyMode, on this device) with Teams' notice after a change; apm::set_tty_mode: a call that starts in TTY mode sends the microphone unprocessed (no echo cancellation, noise suppression, gain control or high-pass) and Opus at 64 kbit/s CBR in its CELT/music mode; Teams' "next call" rule (the running call keeps its mode).
- Verified live on linuxlt: 1:1 calls OST Test 1 → OST Test 2 (two OST instances, each on its own virtual PipeWire mic/speaker), minimodem TDD (45.45 Bd Baudot, 1400/1800 Hz) "OST TTY TEST 151 HELLO" played into the caller's mic and decoded from what the callee played. Clean tones: decoded intact with TTY off and on. Tones in pink noise: TTY off → the callee's audio decodes with spurious characters ("E", "V" before the text: noise suppression/AGC pumping, amplitude 0.70); TTY on → "OST TTY TEST 151 HELLO" exactly, nothing else (amplitude 0.39 = the sender's level). Log: "TTY mode: the microphone goes out unprocessed". All calls ended (hung up the call leg, 202).
- Still open: checking against Teams desktop with a real TTY signal needs audio into/out of winpc's Teams (no virtual audio device there).

- 2026-11-17 (910c0ab): Accessibility card as Teams, kept on the device, with "Changes will be applied for your next call". A call that starts in TTY mode sends the mic unprocessed (no AEC, NS or AGC) and keeps tones intact in the codec.
- Live OST to OST with minimodem TTY tones over noise: garbled with TTY off, exact with TTY on.
- Open (AC2): check against Teams desktop with a real TTY signal. winpc needs a virtual audio device; installing one is authorized.

- 2026-11-17: checked against Teams desktop on winpc through VB-CABLE, in 1:1 calls with ost-test1 in Teams and OST Test 2 in OST. Real TTY tones from minimodem:
  - TTY on in both, OST to Teams and Teams to OST: every message decoded exactly; no gain change (0.71 in, 0.71 out).
  - Baseline, TTY off: Teams' noise suppression removes the tones entirely.
- Teams' devices are restored and TTY is off. VB-CABLE stays installed on winpc but isn't default.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TTY mode works as in Teams, verified against Teams desktop in both directions.

Changes:
- Settings > Accessibility > Teletypewriter (TTY) mode as Teams: kept on this device; shows "Changes will be applied for your next call" after a change; same card height before and after.
- A call that starts in TTY mode sends the mic unprocessed (no echo cancellation, noise suppression or gain control) and keeps tones intact in the codec. This is what Teams' TTY switch does in its media stack.

Tests:
- OST to OST with TTY tones over pink noise: stray characters with TTY off, exact with TTY on.
- OST and Teams desktop with TTY on in both, both directions: exact.
- With TTY off in Teams, its noise suppression removes the tones.
<!-- SECTION:FINAL_SUMMARY:END -->
