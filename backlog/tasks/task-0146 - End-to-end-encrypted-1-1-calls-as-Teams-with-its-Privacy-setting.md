---
id: TASK-0146
title: End-to-end encrypted 1:1 calls as Teams, with its Privacy setting
status: To Do
assignee: []
created_date: '2026-11-15T04:40:00Z'
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
- [ ] #1 Privacy shows 'End-to-end encrypted calls' with Teams' text and Learn more link (https://go.microsoft.com/fwlink/?linkid=2174740), disabled when the tenant admin doesn't allow it
- [ ] #2 The setting is read and saved where Teams keeps it, and Teams on winpc shows the same value
- [ ] #3 A 1:1 call between OST and Teams with both settings on is end-to-end encrypted, shown as Teams shows it in the call
- [ ] #4 Recording and transcription are unavailable in such a call, as in Teams
<!-- AC:END -->
