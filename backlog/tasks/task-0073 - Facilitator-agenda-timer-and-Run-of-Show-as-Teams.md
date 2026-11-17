---
id: TASK-0073
title: Facilitator agenda timer and Run of Show as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T09:29:00Z'
updated_date: '2026-11-17T04:07:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' meeting timer also has an agenda timer (Copilot Facilitator drafts topics; add, rename, delete, reorder, resize, mark discussed, share with consent) and Run of Show (town halls and webinars). Both need Facilitator on (meetingCapability.groupCopilotDetails.enabled); the test tenant has it off, so Teams shows neither there. OST keeps their shared state untouched. Spec: scratchpad timer/spec.md §8–9 (session 744c3998).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With Facilitator on, the agenda timer shows and edits as Teams', verified against Teams in a Facilitator-enabled meeting
- [ ] #2 Run of Show in a town hall or webinar shows and behaves as Teams'
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (dde4544): More > Facilitator > Turn on/off Facilitator and Enable/Disable voice with Teams' requests (ost-test1's Copilot licence is enough); checked live on and off.

Not built: the agenda timer never appeared in Teams in this tenant (its setting to start an agenda yourself is off), so there is nothing to compare against; Run of Show needs a town hall or webinar with Facilitator (TASK-0184); Facilitator ▾ with the new controls.
<!-- SECTION:NOTES:END -->
