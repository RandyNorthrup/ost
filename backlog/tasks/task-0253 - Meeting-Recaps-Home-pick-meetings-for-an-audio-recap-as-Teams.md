---
id: TASK-0253
title: 'Meeting Recaps Home: pick meetings for an audio recap as Teams'
status: Done
assignee:
  - '@recT'
created_date: '2026-11-23T13:48:00Z'
updated_date: '2026-11-23T16:22:00Z'
labels:
  - desktop
  - recaps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0252 (Teams 26304 on winpc, 2026-11-23): with a Copilot licence each Home row shows a checkbox on hover (recap-item-checkbox-slot); picked meetings show Home's selection bar (meeting-recap-home Qs: Clear selection, Generate, at most 8, a warning when none is picked) that makes an audio recap of them (Gs → generateAndPopoutPodcast, origin RecapHome). OST's Home has no checkbox or bar yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Home rows show the checkbox on hover and keep picks as Teams
- [x] #2 The selection bar generates an audio recap of the picked meetings as Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams 26304 on winpc (CDP, tick/untick only): checkbox slot, ticked row, bar, Clear; read meeting-recap-home ns/ts/jn/Yi/Ki and generateAndPopoutPodcast
2. MeetingRecapsView: Copilot entitlement, per-row checkbox (hover/ticked/blocked), picks, bar in the filters' place, Generate -> generateRows, Clear
3. Recap window from Home: Attendance under Shared files (attendance report history), its click opens the meeting chat on Attendance
4. Harness --recaps-home-pick[=..] [--recaps-home-generate --recaps-delete-made]; live on linuxlt: generate from OST TEST 240 + calendar test, delete it
5. Docs, i18n ids, tests
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (recT) Teams 26304 on winpc (CDP, ticked/unticked only): V2 Home (Vi/Ki) shows, with Copilot, a 32x32 Fluent square checkbox 4 in on each row (16 px box at 8, r2, 0.67 #616161; ticked #5B5FC7 / #4F52B2 hovered; opacity 0 until hovered/focused, 1 while ticked, 120 ms). Only the checkbox ticks; a ticked row is #EBEBEB. Blocked (0.45, tooltip): only a recording / no readable transcript ("Audio recap couldn't be generated for this meeting."), or 8 picked ("Select up to eight meetings."). Picks: Home's own PodcastGenerateProvider (Audio recaps and back clears them).
- With picks the filters/search/view toggles give way to the bar (Yi audioRecapGenerationBar: 48 tall at the filters' slot, white, r8, 0.67 #D1D1D1, shadow 8, padding 8 12): Generate audio recap (transparent, headphones 20 + 14/600 #424242; hovered brand + filled glyph) and "X 1/8 selected" (circular outlined; #F5F5F5/#C7C7C7 hovered) which clears. Ask Copilot only with enableRecapHomeCopilot (off). Generate = generateAndPopoutPodcast(all picks, origin RecapHome) -> Audio recaps shows it being made. The V1 bar's "select at least one" warning can't happen in V2.
- Recap window from Home: Shared files list Attendance (artifacts platform adds it on meetingThreadProperties.hasAttendanceReport); Teams' click opens the meeting chat in a pop-out on Attendance. OST: attendance report history -> Attendance; click opens the meeting chat's Attendance tab in the main window.
- Built: MeetingRecapsView picks/checkbox/bar (copilot from licence, also gating the headphones), generatePicked -> generateRows; RecapWindow findAttendance + recapAttendance; Conversation.attendanceOf; harness --recaps-home-pick[=…] [--recaps-home-generate] [--recaps-delete-made]; headphones-20-filled icon.

- Live (linuxlt, ost-test1): Home rows show the checkbox on hover (opacity 1 hovered, 0 otherwise); OST TEST 240 and the calendar test ticked through their checkboxes -> rows #EBEBEB, the bar in the filters' place (48, 100.3, 1116 x 48; Generate 187.9 wide; "2/8 selected" right edge 1103.3 as Teams' 1103.3), "X 2/8 selected" cleared them and the filters came back.
- Generate from the bar (both picked): first run the service answered Failed NoValidMeetingInsightError (as Teams did for 240 in TASK-0212; OST showed "We couldn't generate the audio recap"); second run COMPLETED: Audio recaps showed it being made, played by chapter (Intro, OST TEST 240 recap meeting: Meeting overview, Project coordination…, Outro; 1:00), then the harness deleted it by id (deleted 1). The failed one was deleted with --podcast-cleanup (found 1, deleted 1). No test recap left.
- Recap window from Home: "RECAP attendance 1" -> Attendance under Shared files (as Teams on winpc); pressing it opened the meeting chat on Attendance with the same report as Teams (2 attended, 8:25-8:32 PM, 6m 26s, 5m 23s). The attendance history service answered 503 to the view twice in a row before working; transient.
- Tests: 931 lib + 35 desktop on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting Recaps Home picks meetings for one audio recap as Teams' Recap Home V2 does.

- Each row has Teams' checkbox (with Copilot, from the licence; the headphones now need it too): 32 x 32 four in, shown while the row is hovered or focused and kept while ticked; a ticked row is #EBEBEB; a meeting with only a recording or no transcript you may read, or a 9th pick, is faded with Teams' reason. Picks are Home's own (leaving for Audio recaps clears them).
- With picks the filters and search give way to Teams' bar: Generate audio recap (one recap of every pick with your saved style; Audio recaps shows it being made and plays it) and "✕ n/8 selected" that clears them.
- A recap window opened from Home lists Attendance under Shared files when the meeting has an attendance report; it opens the meeting chat on Attendance (Teams opens that chat in its own window).
- Harness --recaps-home-pick=… [--recaps-home-generate --recaps-delete-made]; --recaps-home also checks Attendance.

Verified live on linuxlt against Teams on winpc: hover, ticking, bar geometry, clearing; one audio recap made from OST TEST 240 + the calendar test meeting, played, then deleted (an earlier attempt the service failed with NoValidMeetingInsightError was deleted too); Attendance listed and opened with Teams' numbers.

Tests: 931 lib + 35 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
