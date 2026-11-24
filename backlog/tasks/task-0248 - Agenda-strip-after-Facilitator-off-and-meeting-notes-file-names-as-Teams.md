---
id: TASK-0248
title: Agenda strip after Facilitator off, and meeting notes file names, as Teams
status: Done
assignee:
  - '@meetO'
created_date: '2026-11-23T06:49:00Z'
updated_date: '2026-11-23T10:01:00Z'
labels:
  - desktop
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0247's live checks: when Facilitator is turned off in a meeting, Teams switches the strip back to the plain timer but OST keeps showing the agenda strip; OST named one test meeting's notes 'Meeting Notes' where Teams names them after the meeting. Also: OST starts a just-made audio recap when generation completes, Teams as soon as its first chapters exist.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Turning Facilitator off switches OST's strip to the plain timer as Teams
- [x] #2 Meeting notes made from OST are named after the meeting as Teams names them
- [x] #3 A just-made audio recap starts playing when Teams starts it (first chapters)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AC1: find what Teams' timer reacts to (lazy-meeting-timer, useMeetingTimer) and refresh OST's timer state on it; keep the strip as Teams does.
2. AC2: find how Teams names meeting notes (call-meeting-notes) and name OST's the same; make the title lookup robust.
3. AC3: follow Teams' PodcastPlaybackManager: progress updates from the AugLoop operation, play by chapter (HLS per chapter via a token proxy), auto-play on HAS_CHAPTERS, wait states.
4. Verify live on linuxlt + winpc; tests; docs; cleanup.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-23 (meetO) AC1: Teams' timer `isFacilitatorOn` (useMeetingTimer 357072) = call meetingDetails.meetingCapability.groupCopilotDetails.enabled (false in a Meet now with ECS meetingCollaboration.enableMeetNowFaAgendaTimerDisabled); without it the agenda drops out of the offered timers; with enableAgendaUbar off (this tenant) the strip view state is left alone, so the ad-hoc timer shows; with no timer active its controls open for editors (lazy-meeting-timer `ws`). OST had the flag but only refreshed it with the timers: show_capability now refreshes the timer JSON's facilitator (refresh_timer_facilitator, meeting_options::facilitator_on); CallWindow keeps the strip/view on the change and opens/closes the controls.
- Live "OST TEST 248 agenda" (ost-test1 OST organizer on linuxlt, OST Test 3 on linuxlt with --agenda-test, Teams on winpc as ost-test1's second device, Facilitator agenda Budget 2 / Permits 2 / Volunteers 1 + Open discussion): Teams Facilitator off -> Teams strip 05:00 > reset with Timer controls open; OST (both instances) visible true, view adhoc, active false within the same second (log "Facilitator changed on=false"); on again -> agenda back in both. The controls-open part was added after this run; a second Facilitator meeting for it did not get the Facilitator bot in (only one person), so it is checked against Teams' code, not live.
- AC2: Teams names notes call.meetingDetails.instanceDetails.subject ?? "Meeting Notes" (527114 createCollabResource). OST's first run reproduced "Meeting Notes.loop": the join answer had no subject yet and the chat lookup got HTTP 429. Now: instanceDetails/eventDetails subject when given, the chat lookup retried on 429, then the calendar event's subject by iCalUid (meeting_info::notes_title, meeting_notes::fill_from_chat). Live: "OST TEST 248 notes.loop", "OST TEST 248 facilitator.loop", "OST TEST 248 recap.loop" named after their meetings.
- AC3: Teams (75874 kt + services-podcast PodcastPlaybackManager) plays by chapter: each chapter's audioFile is an HLS playlist (MPEG-TS segments `…/streams/dcontent_teamspodcast.<n>.0000/content`), growing until #EXT-X-ENDLIST; auto-play on HAS_CHAPTERS (a chapter InProgress/Completed), waits for missing audio / the next chapter. Measured on winpc (AugLoop frames + player button over CDP): first chapter audio 00:34:47, Pause at 00:34:48, waiting at ~00:35:00, chapter 2 at 00:35:03. (A first Teams Generate didn't start at all; not explained.) OST: generate_multi progress callback -> view updates; byChapter playback through StreamProxy::site (site token, segment type sniffed as .ts, growing playlist served from its first segment the first time). Live (rec5/rec6, "OST TEST 248 recap"): auto-play at the first chapter (InProgress, audio), chapter 0 played, waited for chapter 1 audio, played the growing chapter 1, went on past completion (chapter 3 at the end).
- Follow-up TASK-0250: OST lists a meeting across midnight twice in Generate (Teams once, with its 13 tasks chip).
- Tests: 923 lib + desktop tests on linuxlt.
- Cleanup: Facilitator off; Teams left (no call window; OST roster), OST instances left (hung up 202 each); deleted the meetings OST TEST 248 agenda/notes/facilitator/recap with their notes, the misnamed "Meeting Notes.loop" (drive_delete), all test audio recaps (OST's and Teams', 6 + 1 + 1 via deletePodcasts); meetO PipeWire modules unloaded. Left: the meetings' chats and transcripts (stay with the chats); the Facilitator agenda chat message in "OST TEST 248 agenda"'s chat.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Agenda strip, meeting notes names and audio recap auto-play as Teams.

- Facilitator off: OST refreshes the timer's Facilitator flag from the meeting capability update (groupCopilotDetails.enabled, Teams' isFacilitatorOn, incl. the Meet now ECS rule), keeps the strip open on the ad-hoc timer and opens its controls when no timer runs, as Teams; Facilitator on again brings the agenda back. Verified live against Teams on winpc (OST organizer and OST Test 3).
- Meeting notes: named after the meeting as Teams (instanceDetails subject, else the meeting's subject; the chat lookup retried on 429, then the calendar event's subject); live notes for three test meetings were named after them (the first run reproduced the "Meeting Notes" bug).
- Audio recap: Generate's AugLoop updates reach the view; a recap being made plays chapter by chapter from its first chapter (HLS per chapter through a loopback proxy with the site token, MPEG-TS segments, from the start), waiting for audio and next chapters as Teams' PodcastPlaybackManager; Teams measured on winpc starting 1 s after the first chapter's audio.
- Follow-up TASK-0250 (meeting across midnight listed twice in Generate).

Tests: 923 lib + 33 desktop on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
