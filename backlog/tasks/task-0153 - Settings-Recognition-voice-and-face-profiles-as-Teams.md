---
id: TASK-0153
title: Settings > Recognition (voice and face profiles) as Teams
status: To Do
assignee: []
created_date: '2026-11-15T06:00:00Z'
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
- [ ] #1 Settings shows Recognition in Teams' place in the list, with Teams' Voice Recognition and Face Recognition sections, texts and links
- [ ] #2 Start voice capture and Start face capture run Teams' enrollment flows, with consent, and the profiles are saved where Teams saves them
- [ ] #3 The enrollment status shows as Teams shows it, and a profile can be removed as in Teams
<!-- AC:END -->
