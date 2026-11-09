---
id: TASK-0067
title: Meeting timer as Teams (More ▸ Timer)
status: To Do
assignee: []
created_date: '2026-11-09T05:18:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' in-meeting timer: More ▸ Timer shows a strip under the bar with a shared countdown everyone in the meeting sees (ad-hoc timer), the agenda timer built from the meeting's agenda topics, and Run of Show. It syncs through the conversation's meetingStates ("timer") and updateMeetingStates. Research notes: scratchpad pp/timer-research.md (session 744c3998); Teams code: lazy-meeting-timer bundle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 More ▸ Timer shows and hides the timer strip, laid out as Teams' (measured on winpc)
- [ ] #2 Starting, pausing, resuming, resetting, adding time to and cancelling the ad-hoc timer work for everyone, verified live against Teams on winpc in both directions
- [ ] #3 Changing the timer's duration from its controls works as Teams
- [ ] #4 The agenda timer and Run of Show show and behave as Teams, including the empty-agenda state
<!-- AC:END -->
