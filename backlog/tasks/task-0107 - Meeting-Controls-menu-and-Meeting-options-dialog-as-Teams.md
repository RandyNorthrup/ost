---
id: TASK-0107
title: Meeting Controls menu and Meeting options dialog as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T04:48:00Z'
updated_date: '2026-11-11T15:22:00Z'
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
- [x] #2 View more options opens a native Meeting options dialog with Teams' sections, fields and Apply, reading and saving through the options API
- [x] #3 Changing Who can bypass the lobby from OST takes effect (verified with the second test account)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-10: Controls menu (states and toggles per Teams' St/xe/je/gt) and the native Meeting options dialog (7 sections, Teams' labels and value names read from the live dialog) built; verified live as OST Test 1: menu states match, Enable lobby toggled off/on via OST, and with the lobby off OST Test 2 walked into the running meeting (so changes apply live).
- Open for #2: people pickers (co-organizers, specific presenters/producers) show Teams' search box but can't add people yet: the saved shape of selectedPeople wasn't captured (Teams only lets invitees be picked, and the test meeting has none). Allow Copilot shows the API's state; Teams disables it in this tenant (licence), reason not yet read.

- 2026-11-11: people pickers done (9e94da4): the options GET carries the meeting's invitees; Teams' in-meeting picker offers only those (no directory search), selectedPeople posted as {upn, mri, objectId, userType:"Member", tenantId}. Verified live: removed and re-added OST Test 2 as co-organizer from OST (GET confirms each), Teams on winpc shows the pill.
- Allow Copilot: the API marks CopilotMode isLocked (admin policy); Teams shows a lock with "This option is locked by admin." OST now does the same.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' Controls menu and Meeting options dialog, native.

Changes:
- Controls menu (Lock meeting, Enable lobby, Allow all participants to: Present / Chat / Unmute / Cameras, View more options) with Teams' states and toggles, applied to the live meeting.
- Meeting options dialog: Teams' 7 sections, labels and values; Apply posts every option through {mt}/beta/meetings/v1/options.
- People pickers (co-organizers, specific presenters/producers): invitees from the options GET, names from fetchShortProfile, Fluent colourful avatars, Teams' save shape, required-picker validation, planning-group note.
- Locked options (isLocked) get Teams' lock button and tooltip; value _Info strings get an info button; "Unsaved changes" on close.

Tests:
- 428 lib tests pass (new: picked_people_as_teams).
- Live: lobby toggled from OST let OST Test 2 in; co-organizer removed and re-added from OST, confirmed by GET and in Teams on winpc.
<!-- SECTION:FINAL_SUMMARY:END -->
