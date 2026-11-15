---
id: TASK-0153
title: Settings > Recognition (voice and face profiles) as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T06:00:00Z'
updated_date: '2026-11-15T18:32:00Z'
labels:
  - settings
  - calling
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings has a Recognition page (measured on winpc 2026-11-14): 'Voice Recognition' with Teams' consent text, Learn More and Privacy Policy links and 'Start voice capture'; 'Face Recognition' with its consent text and links, 'Create my face profile now' (Takes about 30 seconds.) and 'Start face capture'. These enroll the user's voice and face profiles for the organization (calling biometricEnrollment* / passive consent). Building and verifying it means capturing a real person's voice and face, which OST's testing rules don't allow without the user's say-so: NEEDS A USER DECISION before work starts. Until then OST's Settings has no Recognition page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings shows Recognition in Teams' place in the list, with Teams' Voice Recognition and Face Recognition sections, texts and links
- [x] #2 Start voice capture and Start face capture run Teams' enrollment flows, with consent, and the profiles are saved where Teams saves them
- [x] #3 The enrollment status shows as Teams shows it, and a profile can be removed as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15: user decided: "you are authorized to use the camera irl or anything else you need"; work started.

- Protocol from Teams' bundles (scratchpad bio/SPEC.md) plus live checks: biometricService region GTM (teams.microsoft.com/api/biometric/us), resource 00edd498-…, ring "general", live ECS centre-only face and CTS (Azure Speech) voice path; the service needs a VoiceIsolationSignature version (Teams sends the signature's own with PNSData).
- Measured Teams' four voice-card states, the face card states, the face and voice dialogs, countdown, guide arc and completion step on winpc. The face flow and completion step were captured by feeding Teams' page a generated face (canvas camera via CDP, removed after).
- Tested with a synthetic voice (Piper TTS reading Teams' paragraph, installed on linuxlt) and an AI-generated face (StyleGAN): no real person enrolled. All test profiles and the passive voice opt-in were removed afterwards; Teams shows the initial state again.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Settings ▸ Recognition works as Teams': voice and face profiles in Teams' biometric service.

Engine (api::biometric):
- Teams' biometric service at the region GTM `biometricService`, AAD resource 00edd498-…, `x-ringoverride` from ECS.
- Status (v2 voice/face enroll status), removal (unenroll, me/face/unenroll), passive voice consent (v3/passive/consent/enroll + middle-tier biometric settings), Export (data/v3/export/voice|face).
- Face: cognition token, BSON signature request per head pose, BSON store of photos + signatures (ConsentTextVersion V1).
- Voice: Azure Speech WebSocket (speech.config, speech.context with Teams' paragraph, 16 kHz PCM audio frames, speech.event), Teams' NotEnoughWords/HighErrorRate/NoWords reading, JSON store with speaker and voice-isolation signatures.

Desktop:
- Recognition page: Teams' two cards in every state (consent, badges "Generating/Voice/Face profile complete", Start voice capture opt-in, Opt out with info, Export, Create/Update rows), card heights equal to Teams' in all states; in-meeting message bar.
- Face capture dialog: camera picker, Teams' masked preview, guide pictures and arcs, 3-2-1 countdown, Center/Left/Right with centre-only retries, Teams' error texts.
- Voice capture dialog: mic picker, Teams' paragraph, level meter, Start/End voice capture, Learning, Teams' error texts.
- Teams' completion step.

Tests: api::biometric unit tests; --recognition-states (all card states vs Teams' measurements); --recognition-test with a generated face and a synthetic voice through to storage; examples/biometric for status, removal and passive opt-out.
<!-- SECTION:FINAL_SUMMARY:END -->
