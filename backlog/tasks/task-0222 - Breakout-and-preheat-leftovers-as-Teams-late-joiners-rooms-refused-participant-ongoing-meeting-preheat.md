---
id: TASK-0222
title: >-
  Breakout and preheat leftovers as Teams: late joiners' rooms, refused
  participant, ongoing-meeting preheat
status: To Do
assignee: []
created_date: '2026-11-17T20:43:00Z'
labels:
  - calls
dependencies: []
references:
  - docs/spec/call-and-meeting-window.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0218/0219 left: a participant who joins after rooms are open isn't offered their room; a participant refused by a room was never observed in Teams (OST keeps the main meeting on hold with Resume); Teams' joinOngoingMeetingInPreheatedFlow (on for ost-test1) isn't understood or done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A participant who joins after breakout rooms are open is moved to or offered their room as Teams does, verified live
- [ ] #2 A participant refused by a room sees what Teams shows, observed in Teams and matched
- [ ] #3 What joinOngoingMeetingInPreheatedFlow changes in Teams is found and OST does the same, verified against Teams
<!-- AC:END -->
