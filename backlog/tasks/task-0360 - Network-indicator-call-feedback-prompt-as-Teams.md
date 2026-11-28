---
id: TASK-0360
title: Network indicator call feedback prompt as Teams
status: Done
assignee:
  - '@t361'
created_date: '2026-11-27T17:48:00Z'
updated_date: '2026-11-28T02:54:00Z'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' network-strength popover sometimes (about 1% of calls) asks for call feedback. OST left it out under TASK-0059 because it must not submit call feedback to Microsoft, but the call-quality survey now handles the same case by opting in and opening a GitHub issue (Report a problem). Found by the 2026-11-27 recheck of the work page's left-out list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The network indicator popover shows Teams' feedback prompt under Teams' rule and sampling rate, and answering it routes to OST's Report a problem (GitHub) the way the call-quality survey does; nothing is sent to Microsoft
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams calling bundle (local-nsi vt/Ke): ECS renderLocalNSIFeedbackForm, ring/1% sampling, thumbs block
2. Measure Teams popover live (test meeting winpc + OST test3)
3. Build prompt behind OST call-quality opt-in; not accurate -> Report a problem; popover geometry as Teams; ECS alwaysRender
4. Live check with --join-nsi-feedback
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research (calling bundle 119108, MSTeams 26304): local-nsi vt draws renderFeedbackForm once per indicator mount: ECS calling.renderLocalNSIFeedbackForm && (ring != "general" || Math.random() < 0.01). Ke shows howGoodBlock: "Was this accurate?" (calling:user_feedback_network_strength kb4c90hxq) with transparent thumb like/dislike buttons (aria This was accurate ka0niju4k / This was not accurate kbx9316mo); click sends NsiUserFeedback {userLikes} and hides the block until the popover re-mounts. ECS for ost-test1: renderLocalNSIFeedbackForm true, alwaysRenderLocalNetworkStrengthIndicator true, ring ring3_6 (so always asked); test3 is on general (1 %).
Measured live on winpc 2026-11-27 (Meet now "OST TEST 361 meet now", ost-test1 muted/camera off, OST Test 3 from testpc1 joined): popover 173 wide border-box, padding 10/10/6 + 0.67 border, radius 4, drop-shadow 16, right above the bars at their left; heading 12/16 bold; prompt block padding-top 10, 10/14 #707070, buttons 32x25.33, 20 px thumbs 6 in, hover filled + #5B5FC7; height 68.67 with heading + prompt.
OST: NetworkPopover restyled to those values (tip 12/16, action 10 below, outline 12/16); prompt behind the call-quality opt-in (Surveys on + Ask me about call quality), backend.nsiFeedbackPrompt() with the same rule (calling::quality_survey::nsi_feedback_sampled); "This was not accurate" opens Report a problem (Call quality) with nsi_report_details; nothing to Microsoft. Also ECS alwaysRender: bars for the whole connected call. Harness --join-nsi-feedback (with --cqf-always).

Live check (this branch on testpc1, OST Test 3 in the test meeting, virtual mic ost_t361_mic): --join-nsi-feedback --cqf-always: bars shown all call (ECS alwaysRender true for test3), prompt drawn, popover 173 x 68.67 (= Teams), "This was not accurate" opened Report a problem (Call quality) with the text and details (strength, video, wired, participants, Call health); nothing submitted; reopening shows the prompt again, "This was accurate" hides it and opens nothing. Trace: opted_in=true form_on=true ring="general" (test3: Teams would ask 1 % of the time; ost-test1 is ring3_6 so always). Not checked live: the popover over a real tile's bars (solo meeting has no self tile in Teams or OST; the harness anchors it at the call timer) and the Poor/Bad tip and action layout (network was Good; CSS-derived).
Unit tests nsi_feedback_as_teams, nsi_details_say_what_was_shown pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The network indicator popover now asks Teams' "Was this accurate?" under Teams' rule, routed to OST's Report a problem instead of Microsoft.

Changes:
- calling::quality_survey: nsi_feedback_sampled (ECS renderLocalNSIFeedbackForm; always outside the general ring, else 1 %, one draw per appearance of the bars) and nsi_report_details.
- Backend: nsiFeedbackPrompt (behind the call-quality opt-in: Surveys on + Ask me about call quality; --cqf-always asks every time), nsiAlwaysShown (ECS alwaysRenderLocalNetworkStrengthIndicator), nsiFeedbackDetails; shared cqf_opt_in / call_health_metrics with the survey.
- NetworkPopover.qml restyled to Teams' measured popover (173 wide, padding 10/10/6, 12/16 text) with the prompt row (10/14 #707070, 32 x 25.33 thumbs, filled brand on hover; new thumb-*-20-filled icons). Not accurate -> Report a problem (Call quality); accurate -> nothing sent; either hides the prompt until the popover opens again.
- CallWindow: bars for the whole call when ECS says so; MeetingTile uses nsiVisible. Settings Privacy opt-in text mentions the indicator. Spec docs/spec/feedback-and-help.md section 5; harness --join-nsi-feedback.

Tests: unit tests; live on testpc1 with OST Test 3 in a test meeting; Teams measured live on winpc.
<!-- SECTION:FINAL_SUMMARY:END -->
