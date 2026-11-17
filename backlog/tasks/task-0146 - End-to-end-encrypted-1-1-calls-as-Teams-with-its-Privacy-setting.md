---
id: TASK-0146
title: End-to-end encrypted 1:1 calls as Teams, with its Privacy setting
status: In Progress
assignee: []
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-17T18:15:00Z'
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
- [ ] #3 A 1:1 call between OST and Teams with both settings on is end-to-end encrypted, shown as Teams shows it in the call
- [x] #4 Recording and transcription are unavailable in such a call, as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-17 (0a737fb, 16255e9): Privacy card as Teams (greyed unless the tenant encryption policy lets users choose); setting at {mt}/beta/usersettings/useEndToEndEncryption, synced both ways with Teams on winpc.
- With the setting on, Teams' offer differs by one SDP line, a=x-e2ee. OST adds it to offers and echoes it in answers. Teams called OST Test 2 with both settings on and showed "End-to-end encryption enabled for this call". Both sides hid Transfer, Consult, Copilot, recording and transcription.
- Open (AC3): OST's card has no verification numbers. Teams derives them in native code, and no hash of the DTLS certificates or fingerprints tried matches two captured calls. OST calling Teams with E2EE on is not yet tested live.
- Tenant: UserControlled encryption policy granted to the test accounts only.

- 2026-11-17: two more encrypted Teams to OST calls captured, with OST's key dump. No hash of keys, certificates or fingerprints matches Teams' five-group number. Next: static analysis of Teams' native calling library to find the derivation.
<!-- SECTION:NOTES:END -->
