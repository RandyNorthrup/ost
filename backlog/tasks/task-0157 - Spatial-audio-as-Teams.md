---
id: TASK-0157
title: Spatial audio as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T09:37:00Z'
updated_date: '2026-11-18T00:27:00Z'
labels:
  - calling
  - devices
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings > Devices > Audio settings > 'Spatial audio' (Available with Together mode, Gallery and Speaker view. Learn more): Teams places each speaker's voice to match where their video tile is. OST plays call audio unplaced. Build it natively (stereo placement from the tile positions) and offer the switch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Devices shows 'Spatial audio' with Teams' text and link, kept as Teams keeps it
- [ ] #2 With it on and a stereo output, each participant's voice comes from their tile's side in Gallery, Speaker and Together mode, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (358966 SpatialAudioContainer, 89637 SpatialAudioMixinImplementation, config-prod): Spatial audio is a device-local switch (spatialAudioEnabled, enableSpatialAudioDefaultOn false), shown on desktop, Off and disabled when the speaker isn't spatial capable (stereo, not wireless) or in a 1:1 call. In a call it applies only with a supported layout (Gallery/Speaker, Together mode; FrontRow off), not P2P, and more than one other non-bot person; the call window sends each tile's place on the stage in percent (debounced 240 ms) as [{participantId: audio sourceId, x, y}]. Teams' own media path receives speakers unmixed (codec x-much2/x-much3, PT 113/96, a wasm/slimcore decoder) and pans each stream with an HRTF PannerNode.
- winpc (2026-11-17, DOM): the row sits between dividers after Voice isolation (30.7 under, 30 over), Teams' person-sound-spatial glyph in the icon column centred on it, "Spatial audio" over "Voices will sound like they're coming from where each person is positioned on your screen. Not yet available with wireless headphones. Available with Together mode, Gallery and Speaker view. Learn more" (12 on 17.14), switch centred; winpc shows it Off, enabled.
- Built: calling::spatial (state, positions by audio source, capability, Spatializer: equal-power pan over ±60° plus the interaural delay, gliding per frame); the meeting mix is placed at the mean place of its CSRCs' tiles; call playback now opens the speaker in stereo (audio::start_stereo_at; mono audio plays identically on both channels); CallWindow reports tile centres every 240 ms with Teams' validity rule; Backend set_spatial_state / spatial_audio_capable (PipeWire channels and bus); the Settings row with Teams' text, link and glyph.
- Not as Teams: OST doesn't decode x-much2 (Microsoft's proprietary unmixed-audio codec), so two people talking at once are heard together from between their tiles rather than each from their own; one at a time each comes from their tile. OST has no Together mode yet, so that layout can't be exercised (the rule accepts it when it exists).
- Verified live on linuxlt: meeting "OST calendar test" with two Chrome test guests (Piper speech as their mics), OST joined with spatial on, its playback recorded from a virtual stereo sink (sp1.raw, tools lr.py). Gallery: Guest 1's tile at x 74.8 % → Guest 1 alone: right 7.6 dB louder than left for its whole 20 s; Guest 2's tile at x 50 % → Guest 2 alone: L = R exactly; both together → right 3.5 dB (mean place 62 %). Log: "spatial audio on=true valid=true placed=2 tiles=2". Left the meeting (hung up the call leg, 202).

- 2026-11-17 (910c0ab): the setting row is as Teams (off by default; disabled for non-stereo, Bluetooth and 1:1). The placement follows the active speakers' tile positions in Gallery and Speaker view. Call audio opens in stereo.
- Live: Gallery left and right tiles 7.7 dB to their side, centre even; Speaker view followed the tile.
- Open:
  - Two people talking at once are placed between their tiles. Teams gets each speaker as a separate stream (x-much2, its multi-channel audio) and places each voice; OST must receive and decode those per-speaker streams to match.
  - Together mode is retired in Teams, so there's nothing to place there.

- x-much2 (Teams' MUCHv2, per-speaker meeting audio) reversed and built (2026-11-17):
  - Where: Teams web's pluginless stack selects MUCHv2 while spatial audio is configured (selectCodec), offering `a=rtpmap:113 x-much2/48000/2` (x-much3 is PT 96); its decoder is the healer wasm (teams-modular-packages healer.wasmmodule, CAudioDecode_MUCHv2_c / CCoreAudioHealerMuchv2), natively much_utilities::MuchStreamDecoder in RTMPLTFM.dll.
  - On the wire (captured with OST_OFFER_MUCH=1 + OST_DUMP_RTP, two guests talking): the media processor answers x-much2 and sends all meeting audio as PT 113 from its mix SSRC, CSRCs = active speakers, a one-byte header extension (id 3) counting packets. Payload = u8 stream count; per speaker u8 kind (0x44 = Opus), u32 BE audio source id, u16 BE length, frame = 20 ms mono Opus 48 kHz (SILK WB, TOC 0x48). All 3471 frames of the capture decoded with libopus; each speaker's track transcribed cleanly on its own (whisper).
  - Built: calling::much (parse, payload type, MuchMixer: one Opus decoder and one Spatializer per speaker, mixed in stereo; unknown kinds skipped and logged once), offered in meetings while spatial audio is on and the speaker is spatial capable (spatial::wants_unmixed, set from Backend); the receive loop decodes PT 113 per speaker and places each at their own tile (spatial::azimuth_of). Mixed audio keeps the CSRC placement.
  - Verified live on linuxlt (meeting "OST calendar test", two Chrome test guests, Hide for me so their tiles sit at 25 % and 75 %, OST playback recorded from a virtual stereo sink): log "meeting audio per speaker (x-much2) pt=113". Both talking at once: L-R correlation 0.43 (the earlier mix-placement run: 0.88), the right channel's transcript is Guest 2 alone, the left carries Guest 1. Each alone: +7.6 dB on its side (left) / +5.9 dB (right). Left the meeting cleanly.
  - Limit: OST offers x-much2 at join; turning spatial audio on mid-meeting applies from the next meeting (Teams renegotiates mid-call).
<!-- SECTION:NOTES:END -->
