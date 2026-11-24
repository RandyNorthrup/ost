---
id: TASK-0063
title: Meeting bar AI indicator as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T21:02:00Z'
updated_date: '2026-11-09T00:05:00Z'
labels:
  - calls
  - meetings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' meeting bar shows an indicator after the encryption shield (data-tid ai-control-ubar-indicator, 37.33 px, a crossed sparkle) with the tooltip "AI is turned off and doesn't have access to the meeting" in the test meeting. OST's indicator slot has the shield and the timer only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The indicator shows when Teams shows it, with Teams' glyph, size and tooltip, and its states, read from Teams' code and the meeting data
- [x] #2 Teams' recording indicator (transcript or recording, and who started them) shows beside it while the meeting is transcribed or recorded
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read the AgentsControlIndicator, its popover and the RecordingIndicator in Teams' code; measure them on winpc in each state
2. Find where the transcript state arrives (live capture while starting/stopping transcription and recording)
3. Parse copilotMode, groupCopilotDetails and the call recorder's processingModes; decide visibility from meetingDetails
4. Add the indicators and the Meeting AI menu to the call bar
5. Verify live with transcription and recording started and stopped from winpc
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Transcript/recording state: the call recorder joins as a hidden 28: participant; its endpoint's endpointMetadata.processingModes (realTimeTranscript, recording, copilot) go Active/Inactive with the starter's userId. Captured live.
- Visibility (J3 + 572777): meetings only; Meet now, or non-channel meetings with an iCalUid; not E2EE. The conversation service sends no isPrivateMeeting, so non-channel counts as private.
- No LockMeetingIndicator in Teams' live layout config, so a locked meeting shows no lock in the bar.
- Verified live on linuxlt against winpc: off state; transcription started -> lit + menu with Copilot/Recap checked; recording + transcription -> recording ring and "Recording and transcription started by OST Test 1."; stop -> back to off.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Meeting bar AI indicator and recording indicator, as Teams shows them.

Changes:
- meeting_options: copilotMode / groupCopilotDetails in MeetingCapability; shows_ai_indicator() from meetingDetails (Meet now, private scheduled with iCalUid, not channel/ad hoc/E2EE).
- roster: Processing from the call recorder's processingModes (transcript, recording, Copilot, with who started them), with Teams' indicator state and tooltip strings.
- outgoing: tracks the recorder per participant from the join response and roster updates.
- backend: callAiIndicator / callAiAvailable / callAiFacilitator / callAiOn, callRecordingState / callRecordingTip.
- QML: recording indicator and AI indicator in the bar's indicator slot (timer shifts as in Teams), shared IndicatorTip, new AiPopover ("Meeting AI" menu, read-only for OST as for unlicensed Teams users); --join-ai harness.
- Spec §1.8a; NOTICE lists the Teams-sourced glyphs.

Tests:
- cargo test --lib calling:: (new: call_recorder_processing, recording_indicator_as_teams_words_it, ai_indicator_meetings)
- Live: OST in the test meeting while winpc started/stopped transcription and recording; captures compared with Teams.
<!-- SECTION:FINAL_SUMMARY:END -->
