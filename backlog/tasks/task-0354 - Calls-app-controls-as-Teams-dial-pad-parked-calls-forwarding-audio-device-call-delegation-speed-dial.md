---
id: TASK-0354
title: >-
  Calls app controls as Teams: dial pad, parked calls, forwarding, audio device,
  call delegation, speed dial
status: In Progress
assignee:
  - '@claude-task-0354'
created_date: '2026-11-27T17:31:00Z'
updated_date: '2026-11-27T18:08:00Z'
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
- [ ] #1 B-01: Calls app: dial pad and number entry for Teams Phone users, as Teams desktop does it, checked side by side
- [ ] #2 B-02: Calls app: "Parked calls" button under the dial pad, as Teams desktop does it, checked side by side
- [ ] #3 B-03: Calls app: call forwarding quick menu ("Don't forward ▾"), as Teams desktop does it, checked side by side
- [ ] #4 B-04: Calls app: audio device button ("Custom Setup ▾" with Device settings), as Teams desktop does it, checked side by side
- [ ] #5 B-05: Calls app: Intelligent call delegation banner and onboarding pane, as Teams desktop does it, checked side by side
- [ ] #6 B-10: Calls app: speed dial empty-state illustration, as Teams desktop does it, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams 26304 bundles (DialpadContainer, CallForwardingSettings, AudioDeviceSettings, PA onboarding/banner, Nova speed dial) for gating, strings and behaviour; measure the audit screenshots at 1x.
2. Backend: calling policy adds pstn/park/forwarding (Teams callingSupportService checks); PSTN dial-out call (Placement::Phone, outgoing::call_phone); PipeWire audio device groups; Copilot licence flag for PA eligibility.
3. QML: CallsDialPane (picker, keypad, Call, Parked calls, forwarding menu, device menu), PaPane (banner pane: splash, Voice, Exemptions, Review, done, summary), speed dial illustration; drop the header ··· menu.
4. Unit tests, build on a build box, live side-by-side on linuxlt vs Teams.
5. PR, CI, Codex.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (Teams 26304 bundles on testpc1): dial pad shows when callingSupportService.isPSTNCallingAllowed (allowPrivateCalling, isSfbCloud, isEvEnabled, Online pstnType or own trunk); placeholder dialpad_placeholder vs _no_pstn; keys append to the picker, holding 0 for 1 s types +; Call is enabled with someone picked or any text, text-only dials 4:<number>. Parked calls (UnparkCallButtonRenderer) needs CallParkEnabled (teamsCallParkPolicy.allowCallPark) and EV. Forwarding quick menu (non-enhanced, ECS default): header Forwarding, Don't forward / Forward to voicemail / call group / delegates / Forward to <favourite>, More Settings -> Settings > Calls; hidden when isForwardingAllowed is false or Intelligent call delegation is on. Audio device menu: Audio Devices header, paired mic+speaker devices, Custom Setup (checked) when mic and speaker are on different devices, Device settings. PA banner when isUserPAEligible (ECS enablePersonalAttendant, Copilot licence, policy); onboarding splash/Voice/Exemptions/Review/confirm. Speed dial empty state: evergreen avatar-add-multiple illustration, 20rem tall.
- Teams desktop on winpc/testpc1/testpc2 was in use by other agents (CDP sessions open), so measurements come from the audit's 1x screenshots of Teams and the bundle code.
<!-- SECTION:NOTES:END -->
