---
id: TASK-0250
title: >-
  Generate audio recap: meeting across midnight listed once, with its catch-up
  counts, as Teams
status: Done
assignee:
  - '@recQ'
created_date: '2026-11-23T08:47:00Z'
updated_date: '2026-11-23T12:16:00Z'
labels:
  - desktop
  - recaps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0248: OST's Generate audio recap dialog listed "OST TEST 248 agenda" (11:33 PM - 12:03 AM local) twice under This week and without its task count; Teams 26304 lists it once with its 13 tasks chip. Picking it selected both rows, so the recap was made from the same meeting twice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A meeting that spans midnight is listed once in the Generate dialog and on Home, as Teams lists it
- [x] #2 Its catch-up counts (tasks, mentions) show as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Find Teams' list, de-duplication and count rules (useMeetingRecapList, meetingRecapList resolver, getMeetingRecapByDay, Um/Lm/qb) in 26304
2. Build the per-day merge in api::recaps and one node per eventId in MeetingRecapsView
3. Live: a recorded test meeting across midnight, OST vs Teams on winpc; clean up
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (recQ) Teams 26304: Home and Generate share useMeetingRecapList (components-podcast) -> worker meetingRecapList -> getMeetingRecapByDay, one local day per page (today, then fetchMore a day at a time to 30). Each day: user/meetings/contents (top 20) and, with Copilot, the MeetingCatchUp recommendations for the same range (no Top); recommendations become threads (qb: MeetingId as eventId, ICalUid, TranscriptV2 from the GUID in Description, recommendationData counts) and are merged by lower-case iCalUid (Um; Lm keeps the recommendation whose DriveId:DriveItemId is the recording, else one with a file; artifacts without iCalUid drop out). Resolver lists threads with an eventId and recommendationData or Recording/TranscriptV2; node id = eventId. The hook keeps one node per id (W / ye: the older day over the newer, transcripts/recordings only when present), sorted by start; each day's cache refresh is pushed back (artifactsByUserUpdateEvent, latest per id wins).
- Cause of the double row: OST concatenated the days without merging by eventId. Missing chip: OST read one 30-day catch-up call keyed by TeamsThreadId instead of per-day recommendations merged by iCalUid.
- Measured (recap_days example): a meeting's recommendation comes on one day only, matched on when it was recorded: 248 agenda (recorded from 11:33 PM) on its first day; "OST TEST 250 midnight" (11:45 PM - 12:15 AM Nov 22, recorded 3:20 AM Nov 23) on Nov 23 only, 14 tasks.
- Built: api::recaps day_rows / merge_day / recommendation_threads / listed (Teams' Um, Lm, qb, resolver filter), meetings() asks artifacts + catch-up per day, 8 days at a time; rows carry catchUp / actionItemCount / mentionEventCount; MeetingRecapsView.meetingList (one per eventId, older day over newer, counts kept from the day that has them) for the dialog and Home (Home grouped by start day); recapCatchUp removed; example recap_days; RECAPS home lists the Home days.
- Live: "OST TEST 250 midnight" (calendar event 11:45 PM - 12:15 AM across last midnight, OST on linuxlt as ost-test1 with Record and transcribe, the 9 min Piper dialogue into a recQ fake mic). winpc Teams: listed once in the dialog (no chip on its first renders, "14" once its refreshes were in) and on Home ("14"). OST: dialog This week [250 midnight, Yesterday 11:45 PM - 12:15 AM, 14 tasks, thumb], Last week [240, 3 tasks], Friday, November 6 [calendar test] = Teams' settled dialog; Home 2026-11-22 [250] once. Generate with it picked sent 1 meeting (RECAPS generate 1), COMPLETED.
- Seen, not in scope: Teams' Home is V2 (week groups, thumbnails, attendees, files and catch-up chips): TASK-0252.
- Tests: 924 lib + 34 desktop on linuxlt.
- Cleanup: meeting deleted (--call-notes-cleanup: event gone, no notes made), its recording moved to the recycle bin, the test audio recap deleted (1 of 1; none left), recQ PipeWire devices unloaded, OST instances exited by themselves (join harness left the call: recording stopped, then quit). Left: the meeting's chat and transcript (stay with the chat).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Generate audio recap and Meeting Recaps Home list a meeting across midnight once, with its catch-up counts, as Teams.

- The list is built as Teams' meetingRecapList: per local day, the meeting artifacts and that day's Copilot catch-up recommendations, merged by iCalUid (Teams' Um/Lm/qb and the resolver's filter), 8 days at a time; rows carry the task and mention counts (the separate 30-day recapCatchUp call keyed by thread is gone).
- MeetingRecapsView keeps one meeting per calendar event across days (the older day over the newer, as Teams' W/ye), with the counts of the day that has a recommendation (Teams' day refreshes bring it back); Home groups by the day a meeting starts.
- Verified live with a recorded test meeting across midnight ("OST TEST 250 midnight", 14 tasks on its second day only): OST's dialog matches Teams' on winpc (one row, 14 tasks; the other rows and groups the same); Generate sends it once.
- Debug aid: examples/recap_days. Follow-up TASK-0252 (Teams' Home V2 rows and groups).

Tests: 924 lib + 34 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
