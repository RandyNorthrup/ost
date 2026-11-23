---
id: TASK-0262
title: Calendar and app bar polish from the dark calendar pass
status: In Progress
assignee: []
created_date: '2026-11-23T19:37:00Z'
updated_date: '2026-11-23T19:37:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0258: links in an event page's body show Qt's default blue in both themes; the app bar's Chat and Calendar icons are missing in the first frame after start; three dark calendar colours (upcoming event, all-day busy day tint, Month's +N button) come from Teams' model, not a measurement, because ost-test1 had no such events.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Links in event page bodies use Teams' link colours in light, dark and high contrast
- [ ] #2 The app bar shows all its icons from the first frame after start, as Teams
- [ ] #3 Upcoming events, all-day busy days and Month's +N button match Teams in dark, measured with test events
<!-- AC:END -->
