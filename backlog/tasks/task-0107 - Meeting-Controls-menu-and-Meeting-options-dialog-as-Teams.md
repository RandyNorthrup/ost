---
id: TASK-0107
title: Meeting Controls menu and Meeting options dialog as Teams
status: To Do
assignee: []
created_date: '2026-11-11T04:48:00Z'
labels:
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' Controls button opens a native menu (Lock meeting, Enable lobby, Allow all participants to: Present / Chat / Unmute themselves / Turn on their cameras, View more options), and View more options opens a native Meeting options dialog (Meeting access, Roles, Production tools, Participation, Recording & transcription, Copilot and other AI, Accessibility) backed by GET/POST {mt}/beta/meetings/v1/options/{tenant}/{organizer}/{thread}/0/0. OST's Controls opens the web page instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Controls opens Teams' menu with the same items and states, and each item works against the live meeting
- [ ] #2 View more options opens a native Meeting options dialog with Teams' sections, fields and Apply, reading and saving through the options API
- [ ] #3 Changing Who can bypass the lobby from OST takes effect (verified with the second test account)
<!-- AC:END -->
