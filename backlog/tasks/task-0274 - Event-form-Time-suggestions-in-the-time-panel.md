---
id: TASK-0274
title: 'Event form: Time suggestions in the time panel'
status: To Do
assignee: []
created_date: '2026-11-24T10:07:00Z'
labels:
  - desktop
  - calendar
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0271: Outlook's event form (Teams' event page) lists Time suggestions under the time panel's fields (rows 715.67 x 40, 48 apart: the day 12/600, the time and length 12 px, how many are free; a series: 'Occurs every Thursday …' with % available). OST's time panel has the fields, All day, Recurring and the repeat, but no suggestions yet. Measurements: docs/spec/calendar.md (time panel).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The time panel lists Teams' time suggestions for the attendees, as Teams does for a one-off event and a series
- [ ] #2 Picking a suggestion sets the event's time
- [ ] #3 Measured against Teams on winpc within 1 px
<!-- AC:END -->
