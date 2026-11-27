---
id: TASK-0349
title: >-
  Camera fails right after a lobby admission (media descriptions go to the old
  call leg)
status: To Do
assignee: []
created_date: '2026-11-27T08:07:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0342's native-format test (2026-11-27). After a meeting's organizer admits OST from the lobby, the media processor moves the call (participant retarget). OST's first camera toggle then posts UpdateMediaDescriptions to the pre-move link and gets HTTP 406, code 481 subCode 10021 "Call is ended" (detail 10109 "Participant retarget was successful"). OST shows "Your camera failed". A later toggle, after another re-offer, succeeds. Teams desktop turns its camera on at once after admission.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After a lobby admission, turning the camera on works the first time, verified live
- [ ] #2 UpdateMediaDescriptions follows the call's current link after a retarget
<!-- AC:END -->
