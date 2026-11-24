---
id: TASK-0266
title: Event page and card details as Teams
status: In Progress
assignee: []
created_date: '2026-11-24T00:59:00Z'
updated_date: '2026-11-24T00:59:00Z'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-0264: Teams' event page button says Send where OST's form says Send update; a recurrence change on a repeating non-meeting event isn't sent through the new UpdateCalendarEvent path; OST's card for your own meeting lacks Teams' organizer and response row ("You're the organizer. / X didn't respond.").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The event page's send button wording matches Teams in every state
- [ ] #2 Changing a repeating non-meeting event's recurrence sends the update to its attendees as Teams does
- [ ] #3 The event card shows Teams' organizer and response row for your own meetings
<!-- AC:END -->
