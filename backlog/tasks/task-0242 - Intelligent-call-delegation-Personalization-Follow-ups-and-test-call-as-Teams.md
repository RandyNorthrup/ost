---
id: TASK-0242
title: >-
  Intelligent call delegation: Personalization, Follow-ups and test call as
  Teams
status: Done
assignee: []
created_date: '2026-11-21T17:39:00Z'
updated_date: '2026-11-22T18:26:00Z'
labels:
  - desktop
  - settings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0088 (Teams 26304, measured on winpc 2026-11-21): with Intelligent call delegation on, Teams' settings page also has Personalization (Voice and greeting, Custom instructions with @mentions for contacts and transfers, Make a test call to your delegate) and Skills ▸ Follow-ups (the Bookings page's hours). Their sub-pages live in Teams' personal-attendant-customize bundle and save into personalAttendantSettings and the personal Bookings service ({mt}/beta/personalbookings/bookingsService GET/PUT). OST's ICD page has the switch, Call handling, the spam and recording switches and Notifications only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With Intelligent call delegation on, Settings shows Personalization and Skills ▸ Follow-ups as Teams does, and their sub-pages show and save the same values through the same services
- [x] #2 Make a test call reaches your intelligent call delegation as Teams' test call does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-22 (agent setI) measured on winpc (Teams 26304.1207, ost-test1; ICD turned on for the measuring and off again, the page read Inactive and the Calls card Set up afterwards) and built (f4eeb51 + follow-up; docs/spec/settings.md "Calls > Intelligent call delegation > Personalization, Follow-ups, test call"):
  - ICD page: Personalization card (Wand: Voice and greeting / Custom instructions Manage, the test call row), Skills (TaskListLtr, now with Follow-ups Manage where calendarBookings allows), Notifications (AlertBadge). Icons resolved from Teams' icon module (698714): PersonVoice, TaskListLtr, CalendarEdit, Wand, AlertBadge, VideoPersonCall, Sparkle, ThumbLike/Dislike.
  - Voice and greeting sub-page (language from ECS personalAttendantSupportedLanguages, saved as defaultLanguage; Customize greeting message dialog 700 x 264.7, 200 characters, Teams' placeholder with your first name), Custom instructions sub-page (question, 676.7 x 220 box, Conversation/Scheduling/Protection pills (+ Call handling with ECS) and their suggestions, AI notice, thumbs feedback, n/10000 count, test call, Save; @ offers Add call transfer target / Share contact and a people search, stored as Teams' <route|contact name mri tenantId> tags, shown as @Name), Follow-ups sub-page (enableBookingCalendar switch; length / lead / advance dropdowns; work or custom hours per day with up to five 15-minute slots) - greeting and instructions saved in personalAttendantSettings.calleeName (Base64 UTF-8 JSON) with Teams' whole-object PUT; Follow-ups read with GET and saved with PUT {mt}/beta/personalbookings/bookingsService (worker Y0r/Z0r).
  - Make a test call: Teams' TestCallToPA = a 1:1 call to your own MRI with no thread, audio only; Teams' log shows SlimCore callToPersonalAttendant (botType personalAttendant) and the GraphCommunicationsClient-PersonalAttendantBot answering; its window is titled "Test call with your Call Delegation" with only Mic, More and Leave. OST calls itself with callee endpointType personalAttendant (api calling::outgoing::call_personal_attendant), Teams' title and bar (ubar attendant_test).
  - Verified live on linuxlt (ost-test1 spatest, --seti-pa --seti-pa-call): ICD on, every sub-page shown; greeting "OST TEST 242 greeting", instructions with an @OST Test 2 route tag, language en-GB and follow-up length 45 min saved and read back from the services, then put back (read back); the test call was answered by the attendant (callProgress botInfo, callAcceptance) and stayed connected 20 s with test=true, hung up (202); ICD off again (read back on:false), language en-US.
  - Not done: the chips aren't drawn as Teams' pills inside the box (shown as @Name); custom-hours rows not compared with Teams (only work hours measured); Teams' disabled-state tooltips.

- 2026-11-22 merged (0dcf04a). Mention pills and the custom-hours comparison moved to TASK-0244.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Intelligent call delegation's Personalization, Follow-ups and test call as Teams 26304: Voice and greeting with its greeting dialog, Custom instructions and language save into the delegation settings as Teams does; Follow-ups reads and saves the personal Bookings page; Make a test call calls your own account's personal-attendant endpoint in Teams' window (Mic, More, Leave). Verified live: each value saved, read back and restored; the test call was answered by the delegation; the feature is off again on winpc and in OST.
<!-- SECTION:FINAL_SUMMARY:END -->
