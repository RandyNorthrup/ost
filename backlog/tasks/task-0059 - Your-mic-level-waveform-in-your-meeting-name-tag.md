---
id: TASK-0059
title: Network strength indicator in your meeting name tag (local NSI)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08T11:13:00Z'
updated_date: '2026-11-08T23:22:00Z'
labels:
  - calls
  - meetings
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' own tile name tag can start with an 18 px three-bar glyph (data-testid local-nsi: bars 2 px wide at x 4/8/12, heights 4/7/10, rx 1, 3 px right padding). It shows while the call's network strength isn't Good (or always, by a setting), hides 120 s after it's Good again, and on hover opens a popover with the network state, actions (turn off incoming video), and a feedback prompt. Research where networkStrength comes from (media stack / processor events) and the popover's content, then build it. (Earlier described as a mic waveform; winpc's DOM shows it is the network indicator.)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Your name tag shows the network strength glyph exactly when Teams would (strength not Good, hidden 120 s after recovery), with Teams' bar states
- [x] #2 Hovering it opens Teams' network popover with the same content and actions
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Your name tag shows Teams' network strength bars, rated every second with the algorithm Teams' calling stack uses (receive-side missing share standing in for concealment; the peer's RTCP reports on our audio for jitter and loss; hysteresis and 5 s stickiness), shown while not Good and 120 s after recovery; hover opens Teams' popover (headings, tips, Turn off / Turn on all video).

Tests: network_quality unit tests (levels, hysteresis, stickiness, loss counting); live with 45 % uplink loss via tc netem on linuxlt (Bad within seconds, Good after).

Notes: Teams desktop rates in its native media stack, which isn't observable; this follows its web calling stack. The popover uses Fluent Popover defaults (padding 16) as its exact style classes aren't readable; Teams' feedback prompt (shown 1 % of the time) is left out since OST must not submit call feedback.
<!-- SECTION:FINAL_SUMMARY:END -->
