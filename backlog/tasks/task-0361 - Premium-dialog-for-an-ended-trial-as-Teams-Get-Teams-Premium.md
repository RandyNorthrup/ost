---
id: TASK-0361
title: Premium dialog for an ended trial as Teams (Get Teams Premium)
status: In Progress
assignee:
  - '@t361'
created_date: '2026-11-27T18:15:00Z'
updated_date: '2026-11-28T01:36:00Z'
labels:
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0357 (PR #67, which creates this task). After a Teams Premium trial has ended and the trial licence is gone (isTPManagement false), Teams' ··· > Get Teams Premium opens its post-trial TeamsPremiumModal (components-teams-premium-dialog 'Ii': header picture, premiumBenefits trial_post_trial_dialog_tpc_title/description, the pretrial benefits list, Request a license, Buy now and View all benefits). PR #67 added an OST 'ended' page with that content, laid out like the offer page, and the strings 'Get more with Teams Premium' / 'Request a license anytime to use premium features like these;' (picked by their order in the string file; their keys still need confirming). Still to do: measure Teams' page on a Teams desktop (opening the dialog is safe; never press Request a license: with ECS enableTeamsPremiumAutoLicenseRequest it sends a request to the admin) and match its geometry and strings. Also check whether Teams hides the title-bar Premium pill at narrow window widths (seen on testpc1 at 1024 px; Dse's second argument from the more-options button state) and match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Title-bar Premium pill shows or hides at the same window widths as Teams desktop
- [ ] #2 Get Teams Premium after an ended trial shows Teams' post-trial page with Teams' strings and geometry, checked side by side without sending a licence request
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 post-trial modal (Ii) and title bar pill (Wse/Dse/Bnt) code; resolve string keys
2. Measure the post-trial page and its benefits view live on winpc (CDP, never Request a license)
3. Match geometry, strings, button gates (ECS + policy) and the pill width/120 s rule, marks only once shown
4. Live check OST side by side; harness --premium-test / --premium-pill-test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built so far: PR #67 added the post-trial 'ended' page for Get Teams Premium (PremiumDialog.qml) with provisional strings; measuring Teams' page, confirming the string keys and the pill's narrow-width rule (TitleBar.qml shows it whenever premiumPill is set) are left.
<!-- SECTION:NOTES:END -->
