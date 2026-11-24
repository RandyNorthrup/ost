---
id: TASK-0134
title: 'Settings ▸ Recognition: voice and face profiles as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-14T04:28:00Z'
updated_date: '2026-11-15T21:00:00Z'
labels:
  - desktop
  - settings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Settings has a Recognition page (measured on winpc 2026-11-13): Voice Recognition and Face Recognition cards, each with Microsoft's biometric consent text (Learn More, Privacy Policy) and Start voice capture / Start face capture; face also shows 'Create my face profile now — Takes about 30 seconds'. The buttons enrol a voice profile (recorded speech) or a face profile (camera) with Microsoft's service. OST lists the other pages; this one needs the enrolment protocol researched (without completing an enrolment on a real person) before it can be built.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings lists Recognition after App permissions with Teams' two cards and wording
- [x] #2 Start voice capture and Start face capture enrol, show and delete profiles through the same service Teams uses
- [x] #3 Verified side by side with Teams on winpc
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15: duplicate of TASK-0153, which built it (8014b9d): the Recognition page in all of Teams' card states (heights equal to Teams' on winpc), face and voice enrolment, status, opt-out, export and removal through Teams' biometric service.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done as TASK-0153 (8014b9d): Settings ▸ Recognition with Teams' Voice and Face Recognition cards, enrolment, status and removal through Teams' biometric service, measured against Teams on winpc.
<!-- SECTION:FINAL_SUMMARY:END -->
