---
id: TASK-0242
title: >-
  Intelligent call delegation: Personalization, Follow-ups and test call as
  Teams
status: In Progress
assignee: []
created_date: '2026-11-21T17:39:00Z'
updated_date: '2026-11-22T17:01:00Z'
labels:
  - desktop
  - settings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0088 (Teams 26304, measured on winpc 2026-11-21): with Intelligent call delegation on, Teams' settings page also has Personalization (Voice and greeting, Custom instructions with @mentions for contacts and transfers, Make a test call to your delegate) and Skills ▸ Follow-ups (the Bookings page's hours). Their sub-pages live in Teams' personal-attendant-customize bundle and save into personalAttendantSettings and the personal Bookings service ({mt}/beta/personalbookings/bookingsService GET/PUT). OST's ICD page has the switch, Call handling, the spam and recording switches and Notifications only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With Intelligent call delegation on, Settings shows Personalization and Skills ▸ Follow-ups as Teams does, and their sub-pages show and save the same values through the same services
- [ ] #2 Make a test call reaches your intelligent call delegation as Teams' test call does
<!-- AC:END -->
