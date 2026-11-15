---
id: TASK-0149
title: Automatic work location (Privacy) where the tenant allows it, as Teams
status: To Do
assignee: []
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-15T22:24:00Z'
labels:
  - settings
  - presence
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the tenant's work-location detection policy is on (ECS places.enableWorkLocationDetectionPolicy with enableAutoDetectPlaceWifi), Teams' 'Manage my work location' card has a toggle to update the work location automatically from the office Wi-Fi/peripherals (userPreferences placesSettings.autoUpdateLocationPreference), with a Learn more dialog. The scnetsolutions tenant has the policy off, so OST shows Teams' 'turned off by your IT department' text and the Outlook link; this task covers the policy-on case.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With the policy on, the card shows Teams' automatic work location toggle and Learn more dialog
- [ ] #2 The toggle is saved where Teams keeps it (placesSettings.autoUpdateLocationPreference)
- [ ] #3 With it on, OST sets the work location from the detected place as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 tenant (user: "you are authorized to adjust anything in the test tenant to unblock us"): TeamsWorkLocationDetectionPolicy 'OST test accounts' (EnableWorkLocationDetection true) created with Teams PowerShell and granted to ost-test1 and ost-test2 only (Global stays off).
<!-- SECTION:NOTES:END -->
