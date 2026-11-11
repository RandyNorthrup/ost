---
id: TASK-0107
title: Meeting Controls menu and Meeting options dialog as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-11T04:48:00Z'
updated_date: '2026-11-11T06:35:00Z'
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
- [x] #1 Controls opens Teams' menu with the same items and states, and each item works against the live meeting
- [ ] #2 View more options opens a native Meeting options dialog with Teams' sections, fields and Apply, reading and saving through the options API
- [x] #3 Changing Who can bypass the lobby from OST takes effect (verified with the second test account)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10: Controls menu (states and toggles per Teams' St/xe/je/gt) and the native Meeting options dialog (7 sections, Teams' labels and value names read from the live dialog) built; verified live as OST Test 1: menu states match, Enable lobby toggled off/on via OST, and with the lobby off OST Test 2 walked into the running meeting (so changes apply live).
- Open for #2: people pickers (co-organizers, specific presenters/producers) show Teams' search box but can't add people yet: the saved shape of selectedPeople wasn't captured (Teams only lets invitees be picked, and the test meeting has none). Allow Copilot shows the API's state; Teams disables it in this tenant (licence), reason not yet read.
<!-- SECTION:NOTES:END -->
