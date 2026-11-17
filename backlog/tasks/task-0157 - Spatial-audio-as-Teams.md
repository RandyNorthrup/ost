---
id: TASK-0157
title: Spatial audio as Teams
status: To Do
assignee: []
created_date: '2026-11-15T09:37:00Z'
updated_date: '2026-11-17T23:01:00Z'
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
- [ ] #1 Devices shows 'Spatial audio' with Teams' text and link, kept as Teams keeps it
- [ ] #2 With it on and a stereo output, each participant's voice comes from their tile's side in Gallery, Speaker and Together mode, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (358966 SpatialAudioContainer, 89637 SpatialAudioMixinImplementation, config-prod): Spatial audio is a device-local switch (spatialAudioEnabled, enableSpatialAudioDefaultOn false), shown on desktop, Off and disabled when the speaker isn't spatial capable (stereo, not wireless) or in a 1:1 call. In a call it applies only with a supported layout (Gallery/Speaker, Together mode; FrontRow off), not P2P, and more than one other non-bot person; the call window sends each tile's place on the stage in percent (debounced 240 ms) as [{participantId: audio sourceId, x, y}]. Teams' own media path receives speakers unmixed (codec x-much2/x-much3, PT 113/96, a wasm/slimcore decoder) and pans each stream with an HRTF PannerNode.
- winpc (2026-11-17, DOM): the row sits between dividers after Voice isolation (30.7 under, 30 over), Teams' person-sound-spatial glyph in the icon column centred on it, "Spatial audio" over "Voices will sound like they're coming from where each person is positioned on your screen. Not yet available with wireless headphones. Available with Together mode, Gallery and Speaker view. Learn more" (12 on 17.14), switch centred; winpc shows it Off, enabled.
- Built: calling::spatial (state, positions by audio source, capability, Spatializer: equal-power pan over ±60° plus the interaural delay, gliding per frame); the meeting mix is placed at the mean place of its CSRCs' tiles; call playback now opens the speaker in stereo (audio::start_stereo_at; mono audio plays identically on both channels); CallWindow reports tile centres every 240 ms with Teams' validity rule; Backend set_spatial_state / spatial_audio_capable (PipeWire channels and bus); the Settings row with Teams' text, link and glyph.
- Not as Teams: OST doesn't decode x-much2 (Microsoft's proprietary unmixed-audio codec), so two people talking at once are heard together from between their tiles rather than each from their own; one at a time each comes from their tile. OST has no Together mode yet, so that layout can't be exercised (the rule accepts it when it exists).
- Verified live on linuxlt: meeting "OST calendar test" with two Chrome test guests (Piper speech as their mics), OST joined with spatial on, its playback recorded from a virtual stereo sink (sp1.raw, tools lr.py). Gallery: Guest 1's tile at x 74.8 % → Guest 1 alone: right 7.6 dB louder than left for its whole 20 s; Guest 2's tile at x 50 % → Guest 2 alone: L = R exactly; both together → right 3.5 dB (mean place 62 %). Log: "spatial audio on=true valid=true placed=2 tiles=2". Left the meeting (hung up the call leg, 202).
<!-- SECTION:NOTES:END -->
