---
id: TASK-0344
title: Join with a meeting ID fails when the lobby holds you
status: To Do
assignee: []
created_date: '2026-11-27T04:51:00Z'
labels:
  - bug
  - calls
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0342 (2026-11-26): with the Meet-now meeting set to Only organizers and co-organizers bypass the lobby, OST Test 3 joining by meeting ID and passcode failed twice with "We couldn't find a meeting with that ID and passcode." The log said "join with an ID: The meeting's conversation named no thread" (signaling.rs, the meeting-code conversation lookup). The same meeting joined fine by its meetup-join link and waited in the lobby, and by ID whenever the lobby didn't apply.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Joining by meeting ID and passcode reaches the lobby when the meeting holds you there, as Teams does, verified live
<!-- AC:END -->
