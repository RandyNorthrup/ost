---
id: TASK-0252
title: >-
  Meeting Recaps Home as Teams: week groups, catch-up chips, people and
  thumbnails
status: Done
assignee:
  - '@recS'
created_date: '2026-11-23T11:53:00Z'
updated_date: '2026-11-23T14:08:00Z'
labels:
  - desktop
  - recaps
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0250 (winpc, Teams 26304, 2026-11-23): Teams' Meeting Recaps Home groups meetings like the Generate dialog (This week, Last week, then each older day; its meeting-recap-home Ye), and each row shows the recording's thumbnail with the date tile over it, the attendees' avatars, a files chip (paperclip and a count) and the catch-up chips (mentions, tasks) before the headphones and Recap. OST's Home still groups per day and shows only the date tile, title, subtitle, headphones and Recap.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Home groups meetings into This week, Last week and older days as Teams
- [x] #2 Home rows show the thumbnail, attendees, files and catch-up chips as Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure Teams 26304 Home V2 on winpc (CDP, read-only) and read meeting-recap-home (row So/Nn/es/oa/va/$o, grouping Ye, greeting tr) and the worker (meetingFiles le, recommendation qb)
2. api::recaps: rows carry files (MeetingChat/MeetingStage/Notes), recordings, access state, and the recommendation's speakers, tasks, mentions and reasons
3. MeetingRecapsView Home: Teams' header (greeting hours, gradient), card with week groups, V2 rows (preview with thumbnail/date tile/state badge, title, subtitle, speakers, files/mention/task chips with popovers, reason tag, Go to chat on hover, headphones, Recap)
4. What each opens: title/thumbnail/Recap -> recap window; chips -> popovers (items open the recap); files -> Attached popover; Go to chat; headphones -> audio recap of the meeting
5. Live on linuxlt vs winpc; tests; docs
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (recS) Teams 26304 Home is V2 (enableRecapHomeV2): "Hello, {first}" (greeting by hour: 5-12 morning, 12-17 afternoon, 17-22 evening, else Hello), a radial-gradient background, the list in a white card (radius 12) grouped as the Generate dialog (Ye: This week, Last week, else each day). Row (84 + divider, hover #F5F5F5 r8): Copilot checkbox on hover, preview 104x60 (#E8EBFA r8: the recording thumbnail c126x72 of the recommendation's recording else the first, the date tile 36x36 over it; without a thumbnail a transcript-only or lock badge), title 14/600 #424242 (opens the recap window), subtitle 12 #616161, speakers (recommendationData.speakers, 16 px, 3 inline else +n) below; from 60%: files chip (meetingFiles = MeetingChat/MeetingStage/Notes resources; popover "Attached"), mention and task chips (counts = the recommendation's items; popover with the items, AI disclaimer and feedback), reason tag; right: Go to chat (hover), headphones (generates an audio recap of the meeting), Recap.

- Data: the catch-up recommendation now carries its tasks (Headline, DisplayCleanContent, OwnerDisplayName), mentions (Teams' p: Snippet with the name found again), speakers and reasons (Type as ATTENDED / MISSED_MEETING); rows carry files (meeting_files: MeetingChat/MeetingStage/notes resources; the service leaves a note's id empty, Teams then uses mcoResourceId), recordings, thumb (the catch-up's recording, else the first), access (NoPermission / Good / TranscriptOnly). ECS for ost-test1: enableRecapHomeV2, ChatIcon, SpeakersBelowMetadata, FilesPopover, FlatButton on; Podcast enableAudioRecapFreDialog unset (headphones generate directly).
- Built: MeetingRecapsView Home V2 (wash, greeting hours, pills, card with its own scroll, weekGroups shared with the dialog, rows, chip/files/people popovers, Go to chat, headphones -> generateRows, Recap/title/thumbnail -> recap window), filters and search as Teams; Home asks more days while the list doesn't fill the card; RecapWindow startTab mentions/notes; Conversation.openRecapRef(ref, tab); harness --recaps-home[=subject] [--recaps-home-tab=notes|mentions]; recap_days RECAP_RAW=1.
- Live (linuxlt, ost-test1, vs winpc Teams): groups Last week [OST TEST 240: transcript-only badge, O3 speaker, files 1, tasks 3] and Friday, November 6 [calendar test: thumbnail, files 1], "Loaded all meetings…": same rows, chips, popover sizes (files 249 x 69, tasks 321 wide with 3 items) and text as Teams; Recap opens the recap window (AI summary; Notes from a note), Go to chat opens the meeting chat. Teams also lists "OST TEST 250 midnight" from its local cache: its event was deleted in TASK-0250 and the service no longer returns it (recap_days), so OST doesn't.
- Not checked live: headphones (would make an audio recap), mentions popover (no meeting with mentions in the last 30 days), the lock badge and reason tags.
- Follow-up: TASK-0253 (Home's checkbox and selection bar). Recap window opened from Home lacks Teams' Attendance under Shared files.
- Tests: 926 lib + 35 desktop on linuxlt.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting Recaps Home is Teams' Recap Home V2: week groups, and rows with the recording's thumbnail, who spoke, the files and catch-up chips, and what each opens.

- api::recaps: the catch-up recommendation keeps its tasks, mentions, speakers and reasons; Home rows carry the meeting's files (notes, stage and chat files), its recordings, the thumbnail's recording and whether you may open it (Teams' ot.t).
- MeetingRecapsView Home: Teams' brand wash and greeting hours ("Hello, …" late at night), the filter pills and search (client side, as Teams), the list in a scrolling card grouped This week / Last week / each older day (shared with the Generate dialog), 84 px rows with the preview (thumbnail under the date tile, or a transcript / lock badge), title, when, speakers (16 px, +n popover), files / mentions / tasks chips with their popovers, reason tag, Go to chat on hover, headphones (an audio recap of the meeting) and Recap.
- The title, thumbnail, Recap and a task open the recap window; a mention opens it on Mentions, a meeting note on Notes; Go to chat opens the meeting chat.
- Verified live on linuxlt against Teams on winpc (same groups, rows, chips and popovers); Teams additionally shows a deleted test meeting from its own cache.
- Harness --recaps-home; examples/recap_days RECAP_RAW=1. Follow-up TASK-0253 (Home selection bar).

Tests: 926 lib + 35 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
