---
id: TASK-0067
title: Meeting timer as Teams (More ▸ Timer)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T05:18:00Z'
updated_date: '2026-11-09T09:30:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' in-meeting timer: More ▸ Timer shows a strip under the bar with a shared countdown everyone in the meeting sees (ad-hoc timer), the agenda timer built from the meeting's agenda topics, and Run of Show. It syncs through the conversation's meetingStates ("timer") and updateMeetingStates. Research notes: scratchpad pp/timer-research.md (session 744c3998); Teams code: lazy-meeting-timer bundle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 More ▸ Timer shows and hides the timer strip, laid out as Teams' (measured on winpc)
- [x] #2 Starting, pausing, resuming, resetting, adding time to and cancelling the ad-hoc timer work for everyone, verified live against Teams on winpc in both directions
- [x] #3 Changing the timer's duration from its controls works as Teams
- [x] #4 Agenda timer and Run of Show behave as Teams where Facilitator is off (hidden, their shared state kept); the Facilitator views follow in TASK-0073
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research: Teams' lazy-meeting-timer bundle read into scratchpad timer/spec.md (state model, every action's object, normalisation with the service stamp, visibility rules, styles, publish path) by a research subagent; layout and popover measured on winpc.
- Built: calling::meeting_timer (model, actions, Teams' validation, countdown; 5 tests), OutgoingCall updateMeetingStates link + publish, backend call_timer_json with Teams' live clock skew, MeetingTimerStrip.qml + TimerSpin.qml, More ▸ Timer, a synthesised time-up chime (OST ships no Microsoft sounds).
- Verified live with winpc Teams: start/pause/resume/+1 min/cancel/new 1:30/pause from OST; resume and pause from Teams; a 10 s timer running out on both (negative count, Cancel timer for everyone, Time's up!).
- Facilitator is off in the tenant (groupCopilotDetails.enabled false), so Teams shows no agenda or Run of Show; AC#4 reworded, the Facilitator views moved to TASK-0073.
- Harness: --join-timer, --join-timer-remote.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Teams' meeting timer (More ▸ Timer), shared with everyone in the meeting.

Changes:
- calling::meeting_timer: Teams' timer model (the shared `timer` meeting state, normalisation with the service's stamp, its validation), every ad-hoc action (start, pause, resume, reset, +N min, cancel, new length, cancel at time-up) and its countdown text.
- OutgoingCall: keeps updateMeetingStates and the timer from the join response and updates; publishes changes as Teams does.
- Backend: call_timer_json (with Teams' clock-skew measure), meeting_timer actions, timer_chime; capability exposes "everyone presents".
- QML: MeetingTimerStrip (countdown trigger, play/pause/reset, track with Paused / Time's up!, the Timer controls popover with minutes/seconds boxes), More ▸ Timer and Teams' show/hide rules; screen-reader announcements.
- ringtone::chime for time-up.
- Spec: call-and-meeting-window.md §1.8h.

Tests: cargo test --lib (339 pass, 5 new); live runs against winpc Teams both ways.

Follow-up: TASK-0073 (Facilitator agenda timer and Run of Show).
<!-- SECTION:FINAL_SUMMARY:END -->
