---
id: TASK-0152
title: Record a voicemail greeting (Settings > Calls) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T05:45:00Z'
updated_date: '2026-11-17T22:42:00Z'
labels:
  - calling
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > Calls > Voicemail > 'Record a custom greeting' / 'Record a greeting' starts a call to your own voicemail (GraphQL startCall {conversation: {id: your user id}, isVoicemail: true}), where the voicemail system lets you record the greeting. OST's calling can't place that voicemail call yet, so the row is left out of the card until it can.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Voicemail shows 'Record a custom greeting' with Teams' 'Record a greeting' button above the greeting language
- [ ] #2 The button places a call to your voicemail as Teams does, where the greeting can be recorded, and the call can be ended normally
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams (settings-app + calling stack): Record a greeting = startCall({conversation: {id: self}, isVoicemail: true}) → startVoicemailCall → startCallToVoicemail({voicemailResourcePath: "greeting"}). The request names the callee {id: self, endpointType: "voicemail"} with callInvitation.voicemailSettings {localResourcePath: "greeting"}; Teams' voicemail service (28:14524421-…) answers. The window is titled "Voicemail"; isVoicemailGreeting hides Chat, People, hold, transfer and park.
- Built: the Voicemail card's first row "Record a custom greeting" / "Record a greeting" (Teams' geometry, above the greeting language); outgoing::call_own_voicemail (signaling CallExtras.voicemail); Backend record_voicemail_greeting; the ubar fact `voicemail`; the call opens with its dial pad.
- winpc (2026-11-17, DOM only): Teams' voicemail call bar is Mic, Dial pad, More (only Audio settings) and Leave, the dial pad open at the start. OST shows the same controls (its old-controls order; winpc has New meeting controls on).
- Fixed on the way: ICE took the first address that answered. A media processor's relay candidate often answers first and DTLS through it timed out (2 of 3 voicemail calls had no audio). ICE now waits 600 ms for a better path and takes the highest-priority one ("ICE: a better path answered").
- Verified live on linuxlt (--voicemail-greeting-test, call audio on virtual PipeWire devices, prompts transcribed with whisper): menu → 1 → "You have not recorded a personal greeting" → 1 → "Please record your greeting after the tone" → a Piper TTS test greeting → # → played back → 1 "Recording accepted". Then deleted with 3 ("Recording deleted"); the next call says "You have not recorded a personal greeting" again (default restored). Every call ended (hung up the call leg, 202).
<!-- SECTION:NOTES:END -->
