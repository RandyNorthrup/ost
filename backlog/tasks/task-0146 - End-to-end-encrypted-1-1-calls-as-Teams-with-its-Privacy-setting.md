---
id: TASK-0146
title: End-to-end encrypted 1:1 calls as Teams, with its Privacy setting
status: Done
assignee: []
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-17T22:25:00Z'
labels:
  - calling
  - settings
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings > Privacy has 'End-to-end encrypted calls' (GraphQL isE2EECallEnabled / isE2EESettingEnabledByTenantAdmin, mutation with {enable}); a one-on-one call is end-to-end encrypted when both people turn it on, and recording/transcription are then unavailable. OST shows the card only once its calls can actually be end-to-end encrypted, so it is left out of Privacy until then.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Privacy shows 'End-to-end encrypted calls' with Teams' text and Learn more link (https://go.microsoft.com/fwlink/?linkid=2174740), disabled when the tenant admin doesn't allow it
- [x] #2 The setting is read and saved where Teams keeps it, and Teams on winpc shows the same value
- [x] #3 A 1:1 call between OST and Teams with both settings on is end-to-end encrypted, shown as Teams shows it in the call
- [x] #4 Recording and transcription are unavailable in such a call, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-17 (0a737fb, 16255e9): Privacy card as Teams (greyed unless the tenant encryption policy lets users choose); setting at {mt}/beta/usersettings/useEndToEndEncryption, synced both ways with Teams on winpc.
- With the setting on, Teams' offer differs by one SDP line, a=x-e2ee. OST adds it to offers and echoes it in answers. Teams called OST Test 2 with both settings on and showed "End-to-end encryption enabled for this call". Both sides hid Transfer, Consult, Copilot, recording and transcription.
- Open (AC3): OST's card has no verification numbers. Teams derives them in native code, and no hash of the DTLS certificates or fingerprints tried matches two captured calls. OST calling Teams with E2EE on is not yet tested live.
- Tenant: UserControlled encryption policy granted to the test accounts only.

- 2026-11-17: two more encrypted Teams to OST calls captured, with OST's key dump. No hash of keys, certificates or fingerprints matches Teams' five-group number. Next: static analysis of Teams' native calling library to find the derivation.

- 2026-11-17 (e2ee.rs): Teams' derivation recovered from RtmMediaManager.dll: SHA-512 of the two raw DTLS fingerprints sorted by byte, then PBKDF2-HMAC-SHA512 with an empty salt, 16384 iterations, 64 bytes. OST computes it on every E2EE call. Still open: Teams' byte-to-five-group digit formatting. Research tooling is in docs/dev/e2ee-research.

- 2026-11-17 (b9fa5f9): formatting found in the Service Worker cache chunk of Teams desktop. Take the last 16 bytes of the PBKDF2 output, hex-encode, split into 8-hex chunks, parseInt % 100000 padded to 5 digits, then regroup as 5x4. The unit test reproduces both live Teams calls exactly. The encryption card shows the numbers.
- Left for AC3: a live look at OST's card next to Teams' popup in an encrypted call (needs winpc).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
End-to-end encrypted 1:1 calls work with Teams in both directions, showing the same verification numbers as Teams.

Changes:
- Privacy > End-to-end encrypted calls, as Teams: greyed unless the tenant policy lets users choose. Stored at {mt}/beta/usersettings/useEndToEndEncryption, synced both ways.
- With the setting on, OST offers and echoes a=x-e2ee as Teams does. The media is already end-to-end through the DTLS handshake.
- Verification numbers, recovered from Teams' native RtmMediaManager.dll and its Service Worker cached UI chunk:
  - SHA-512 of the two sorted raw DTLS fingerprints;
  - PBKDF2-HMAC-SHA512 (empty salt, 16384 iterations, 64 bytes), keeping the last 16 bytes;
  - five-digit groups from 8-hex chunks, regrouped as 5x4.
  Code in src/calling/e2ee.rs.
- The encryption card follows Teams' popup (280x216). An encrypted call hides recording, transcription, transfer, consult, park, Copilot and apps, as Teams. A cxx-qt naming bug (callE2Ee) had hidden E2EE entirely; fixed.

Tests:
- e2ee unit tests reproduce two live Teams calls exactly; 702 lib tests.
- Live: Teams calling OST and OST calling Teams each showed matching numbers in both apps.

Tenant: UserControlled encryption policy granted to the test accounts only. Switches left off.
<!-- SECTION:FINAL_SUMMARY:END -->
