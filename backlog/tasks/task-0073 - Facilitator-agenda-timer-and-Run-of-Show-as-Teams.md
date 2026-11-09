---
id: TASK-0073
title: Facilitator agenda timer and Run of Show as Teams
status: To Do
assignee: []
created_date: '2026-11-09T09:29:00Z'
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
