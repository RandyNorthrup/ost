---
id: TASK-0227
title: Town hall and webinar leftovers as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-19T14:09:00Z'
updated_date: '2026-11-20T06:51:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0217: in an auto-recorded event's green room Teams shows 'Recording and transcription will begin when the meeting starts.' (OST shows 'Start the meeting whenever you're ready.'); OST registers without answers, so registration forms with questions aren't handled; OST's Discover card for attendees lacks 'By <presenter>'.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An auto-recorded event's green room shows Teams' recording notice
- [x] #2 Registration forms with questions are shown and answered as in Teams, verified live
- [x] #3 Attendees' event cards show 'By <presenter>' as Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-19 (agent c3) research: green-room notice = recorder processingModes state "WaitingForMeetingLive" (527114: recording+transcript -> RecordingAndTranscriptWaitingForMeetingLive "Recording and transcription will begin when the meeting starts"; transcript only / recording only have their own). Alert service shows one alert; Teams layout measured in th2/webinar-wait-dump (318.7 x 62, record glyph 12 in, text 40 in).
- Registration questions (meet-app 1626000..1650000): types Text (input, 255), Note (textarea rows 4, 1000), SingleChoice (RadioGroup), MultiChoice (checkboxes gap 8, required = at least one), Boolean (checkbox, defaultChecked isCheckedByDefault), PromoEmailConsent (checkbox, marginTop 8); Predefined labels from internalName (Address, City, State, ZIP/Post code, Country/Region, Industry, Job title, Organization, Phone number); answers ei(): Boolean bool, MultiChoice list, others String; hasAcceptedTermsOfUse only with termsOfUseUrl. Question ids "predefined-<name>-<ms>" / "custom-<type>-<ms>"; organizer side PATCH events/{id}/registration (update-virtual-event-registration) or registrationInfo in POST events.
- Card "By": meet-app Or/dr: organizers see Organizer / Co-organizer; others By session presenters (no-bypass first, then bypass; hidden, rooms, nameless left out; external email names -> "Guest Speaker"), 2 shown + "+N", tooltip with all when >1; no presenters -> owner displayName.

- Verified live (linuxlt): (1) "OST TEST 227 recording" town hall (ost-test1 organizer, auto-recorded): OST's green room alert = "Recording and transcription will begin when the meeting starts" (record glyph, 318.7 x 62 as Teams); left (202), cancelled. (2) "OST TEST 227 reg questions" webinar by OST Test 2 (Text required, SingleChoice required, MultiChoice, Boolean required, Note, predefined Job title): ost-test1 in OST saw the six questions, empty Register gave "This field is required." on the three required ones, answered and registered ("You're registered!", card Registered); the organizer's registrations list showed all six answers; Unregister put it back. (3) Discover cards: "By OST Test 3" (presenter) and "By OST Test 2" (no presenters: owner). Events cancelled, calendar entries purged (ost-test1, OST Test 2, OST Test 3).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Town hall and webinar leftovers as Teams, verified live.

- Auto-recorded events: the green room shows "Recording and transcription will begin when the meeting starts" in Teams' layout once the recorder waits in the meeting.
- Registration questions: text, note, single and multiple choice, checkbox and predefined fields after Email, with "This field is required." checks and the answers sent in the register request (organizer saw all six answers; Unregister works).
- Discover cards: "By" the session's presenters (two, then +N, all in a tooltip), or the owner when there are none.
- 806 lib + 29 desktop tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
