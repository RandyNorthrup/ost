---
id: TASK-0356
title: >-
  Meetings as Teams: pre-join device pickers and phone audio, alone in Meet now,
  meeting chat pane, More menu
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-27T17:32:00Z'
updated_date: '2026-11-27T21:06:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope B), which compared Teams desktop on winpc (ost-test1, read over CDP) with OST main 7d1c3a38 on linuxlt. Each acceptance criterion is one verified gap. The full entry for each (what Teams does, what OST does, severity, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditB.md, under its B-number, with screenshots in audit/shots-B/ (t-* Teams, o-* OST).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 B-16: Pre-join: mic, speaker and camera pickers and "Test mic and speaker", as Teams desktop does it, checked side by side
- [x] #2 B-17: Pre-join (Meet now): Phone audio is greyed out, as Teams desktop does it, checked side by side
- [x] #3 B-18: Alone in your Meet now: "Invite people to join you" and the invite dialog, as Teams desktop does it, checked side by side
- [x] #4 B-19: Meeting chat pane header: "Meeting chat", private chat tabs, pop-out and chat options, as Teams desktop does it, checked side by side
- [x] #5 B-20: Meeting chat pane shows the previous meeting's chat after you start another meeting, as Teams desktop does it, checked side by side
- [x] #6 B-21: More menu grid lacks Facilitator and Interpreter (new meeting controls), as Teams desktop does it, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
PR 1 (broken + quick): B-18 stage text by Teams' isAdhoc (calling_screen_onlyOneHere_adhoc/_scheduled) + landing element (invite dialog for the alone organizer of a Meet now, else People) + Add participants; B-20 chat pane reset when the call window closes and reload on thread change; B-21 Facilitator grid entry (menu) + Interpreter shown by the ubar facts.
PR 2 (missing features): B-16 pre-join mic/speaker/camera pickers, Test mic and speaker wizard (Teams' TestAudioWizard), Need help?; B-17 Phone audio in Meet now pre-join; B-19 Meeting chat header (title, Add a chat as a tab, Open in new window, More meeting chat options / Allow chat tabs).
Research: Teams 26304 bundles (testpc1 WSL) + live Teams desktop on a free test PC; live OST checks on linuxlt between test accounts with a virtual mic.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- PR 1 (branch task-0356-meetings-parity): B-17/18/19/20/21 written; Teams logic read from its 26304 bundles (stage text keys calling_screen_onlyOneHere_adhoc/_scheduled; landing element; FacilitatorButton menu; AiInterpretationButtonForAll; meeting-relevant-people chat tabs and options).
- PR 2 (branch task-0356-prejoin-audio): B-16 device pickers (audio flyout speakerOnly/microphoneOnly), camera picker, Test mic and speaker wizard (TestAudioWizard state machine, Teams test tone from its CDN, record-and-play-back mic monitor), Need help?.
- testpc1 C: was full (WSL read-only); held its build lock until the coordinator fixed it.

- Live on linuxlt (ost-test1 as organizer, OST Test 2 joining; virtual mic ost_t356_mic, every OST capture stream checked on it), harness --meetnow-parity-test [--meetnow-tab-wait]:
  - B-17: Calendar Meet now pre-join has the link; phone state {available:true}; Phone audio selectable.
  - B-18: stage "Invite people to join you"; landing dialog open over the backdrop with Add participants, both rounds.
  - B-20: round 2 opened with no side pane; Chat then showed its own meeting chat.
  - B-21: grid Record, Transcribe, Facilitator, Interpreter, Timer, Notes, Captions, Rooms, RTT, Get more apps and agents (same as Teams).
  - B-19: "Meeting chat" with the three buttons; Select a participant (No one to show here yet alone); with OST Test 2 in: private tab "OST Test 2" (their 1:1 chat, 49 messages), a test line sent from the tab arrived (50); Options > Allow chat tabs.
  - Fixed on the way: More meeting chat options closed as it opened (header model rebuilt the buttons); privateTab binding loop.

- PR #49 (task-0356-meetings-parity): B-17..B-21. CI green; Codex found 4 issues (shared chat-window timelines, lobby pop-out, Allow chat tabs off, stale group-chat request), all fixed in 74ac8183 and answered.
- PR #53 (task-0356-prejoin-audio): B-16. Live on linuxlt (OST Test 2, --prejoin-audio-test, nothing joined): rows name the devices in use; mic-only / speaker-only flyouts and the camera list open; wizard speaker step plays Teams' CDN test sound on ost_t356_sink; mic step monitor capture on ost_t356_mic, playback on ost_t356_sink; summary "Your audio is ready for the meeting"; Done stops both.
- Teams desktop not re-driven live this session (winpc, testpc1, testpc2 all in use by other agents throughout); the Teams side is from Teams 26304's code/CSS and the audit's Teams desktop screenshots. B-16's wizard has no Teams screenshot to compare: AC #1 stays open until a side-by-side on a Teams desktop.

- #53 head e96fadec rechecked live: pre-join mic flyout meter capture on ost_t356_mic; speaker-step output matches Teams' tone sample for sample at real time (69/69 windows); a 1 s burst into the virtual mic played back once after the pause, no feedback loop.
- #49: E0716 in close_chat_window fixed (0c8b68bb); clippy (workspace and ost-desktop test-harness) clean on a build box; CI green; Codex overflow findings (tab row, picker list) fixed in 0c8b68bb / 638ad2dc.
<!-- SECTION:NOTES:END -->
