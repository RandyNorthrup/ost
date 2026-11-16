---
id: TASK-0211
title: Test call and meeting Copilot leftovers as Teams
status: To Do
assignee: []
created_date: '2026-11-16T23:39:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0141 and TASK-0188 (docs/spec/call-and-meeting-window.md):
- The Echo bot shows as round "EC" initials; Teams shows a square bot avatar. OST can't detect some of Teams' test-call report causes (call drop, device permission, camera freeze).
- Meeting Copilot loads the app as Teams on the web does, not desktop's pre-rendered form (welcome text differs); "Turn on Copilot for everyone?" (only during the meeting) isn't built; userEligibilityInformation and some feature flags go unanswered; in the classic bar Copilot moves into More while its pane is open.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Echo bot's avatar and the test-call report causes match Teams
- [ ] #2 Meeting Copilot opens with Teams desktop's first page, answers all of the app's host messages, and offers Turn on Copilot for everyone as Teams does
<!-- AC:END -->
