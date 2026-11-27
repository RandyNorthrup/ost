---
id: TASK-0347
title: Dial a number from a call's People pane
status: To Do
assignee: []
created_date: '2026-11-27T07:35:00Z'
updated_date: '2026-11-27T17:44:00Z'
labels:
  - calls
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-0345. Teams' 'Invite someone or dial a number' picker lists the number the typed text reads as (e.g. '+167883782', External) first and rings that number into the call (a 4:+number participant). OST's call People pane lists people only. Calling real phone numbers in tests is allowed (user, 2026-11-27). Ringing a number out needs PSTN calling for the test account: Teams Phone Standard is on (trial, Enterprise Voice), but the tenant has no calling plan, Operator Connect or Direct Routing yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Typing a number in a call's People pane shows Teams' number row and picking it rings that number into the call, verified with a test phone number
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27: the user corrected an earlier note: real phone numbers are NOT off limits for tests. Open question to the user: which number to ring, and whether to add a calling plan (purchase/trial) so the test account can dial out.

- 2026-11-27: calling plan bought (Teams Domestic Calling Plan 120 min, assigned to ost-test1). Test calls ring the user's Google Voice number (805) 697-1662. ost-test1 still needs a phone number assigned (in progress).
<!-- SECTION:NOTES:END -->
