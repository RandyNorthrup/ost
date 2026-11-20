---
id: TASK-0199
title: Meeting chat Q&A, Meeting Whiteboard and Breakout Rooms with rooms as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-16T09:43:00Z'
updated_date: '2026-11-20T23:22:00Z'
labels:
  - desktop
dependencies:
  - TASK-0053
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST lists a meeting chat's tabs as Teams (Attendance, Breakout Rooms, Q&A, Meeting Whiteboard) but Q&A and Meeting Whiteboard are Teams' embedded pages, which don't run without a TeamsJS host (TASK-0053): Whiteboard shows "Something went wrong" and Q&A's sign-in fails (AADSTS700054). Breakout Rooms' layout once rooms exist is unmeasured, and Assign participants, Room settings and Import from CSV only point to the meeting window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Q&A and Meeting Whiteboard tabs run in a meeting chat as in Teams
- [ ] #2 Breakout Rooms with rooms created matches Teams' layout, and its Assign participants, Room settings and Import from CSV work from the tab as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far (16a17d0):
- Meeting Whiteboard opens the meeting's own board as Teams: GET {mt}/beta/meetings/fluidboard, Teams' 14 address parameters, changeWhiteboardUrl saved (POST …/meetings/v2/whiteboard), loadingCallback. Checked in a Meeting with OST Test 1 chat: the same board Teams opened.
- Q&A runs; in "OST calendar test" it shows "Q&A is not available for this event", as Teams does.

Left: Breakout Rooms with rooms created (layout, Assign participants, Room settings, Import from CSV).

- 2026-11-20 (callsC) Teams measured on winpc (meeting chat "OST TEST 235 room camera", CDP dumps in scratchpad c235/brdump*.json, settingsdlg/assigndlg*/csvwarn/deldlg.json): rooms as 290x250 cards (white, radius 2, card shadow) from (22.4, 62.73) 16 apart, a 126 tall #5B5FC7 band with a white ··· (238,16: Rename / Room options / Delete), name 16/700 at (20,150), divider at 191, filled person + "n participants" at 210; toolbar Add / Import from CSV (only with rooms) / Remove rooms / Rooms settings (32 px, 5 apart, 20 from the right); unassigned chat members as 32 px pictures 15 px after Assign participants (organizer excluded); Assign participants opens a type step (600 wide: Automatically assign a - b people / Manually assign people to rooms / Let people choose their rooms; Cancel / Next), Manually opens the 700-wide assignment table; Breakout rooms settings is a 600x466.67 dialog (switch rows; presenters note; hours/minutes combos; Save); Remove rooms? 450 wide; Import from CSV with rooms asks "Overwriting rooms and participant assignment" first; Room options opens the room's meetingOptions page in the browser (language, tenantId, organizerId, threadId with ":"->"_", messageId 0).
- Built: BreakoutTab rewritten to those measurements (cards, toolbar, avatars, type step, AssignRoomsDialog with the chat's members, BreakoutSettingsDialog, CSV confirm + BreakoutCsvDialog, Rename/Delete room dialogs, Room options URL from the backend); backend tab state now carries people (chat members but the organizer, roles from meeting options) and each room's options_url; harness --breakout-tab-test (+ --breakout-tab-assign, --breakout-tab-clean).

- 2026-11-20 live (linuxlt, OST Test 2 as organizer of "OST lobby chat test (OST Test 2)", --breakout-tab-test --breakout-tab-assign): people = OST Test 3, OST Test 1 (chat members but the organizer, as Teams lists them); Create 2 rooms -> cards; the assignment type step (600 wide, "Automatically assign 1 person to each room" / Manually / Let people choose) matched Teams' layout; Automatically assigned one person per room (bulk assign 200), cards showed "1 participants" (now "1 participant"), each room had its Room options address; Remove rooms deleted both. Pictures linuxlt /tmp/act/c199. Teams side measured the same day (above).
- Open: dark/high-contrast colours of the cards not measured; Teams' CSV Continue opens its file dialog (OST: the CSV dialog, as the meeting pane); the tab's avatar row for more than one unassigned person (spacing, "+n") not measured.
<!-- SECTION:NOTES:END -->
