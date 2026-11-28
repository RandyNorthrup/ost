---
id: TASK-0361
title: Premium dialog for an ended trial as Teams (Get Teams Premium)
status: Done
assignee:
  - '@t361'
created_date: '2026-11-27T18:15:00Z'
updated_date: '2026-11-28T02:54:00Z'
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
- [x] #1 Title-bar Premium pill shows or hides at the same window widths as Teams desktop
- [x] #2 Get Teams Premium after an ended trial shows Teams' post-trial page with Teams' strings and geometry, checked side by side without sending a licence request
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

Research (MSTeams 26304 bundles, linuxlt ~/teams-26304; live on winpc 2026-11-27 over CDP, ost-test1):
- Post-trial page (components-teams-premium-dialog Ii): keys confirmed premiumBenefits:trial_post_trial_dialog_tpc_title (k77tjtex9) "Get more with Teams Premium" and trial_post_trial_dialog_tpc_description (k6ntwmxkd); buttons discover_try_buy_banner_request_button (k4ks7frn5), discover_try_buy_self_purchase_button_text (k2kmwurg3), trial_pretrial_dialog_tpc_view_benefits_button (k4upc109m).
- Measured (600x600): title h2 at 26,197 548 wide 24/32/700; description 14/20 #424242 centred at 244; features at 287/354/421 (pictures 110, text 177); footer reversed with padding 24 and the inner group padded 24 again: View all benefits subtle at 24,497 stretched 79.33 tall; Buy now 301.72 (106.04 wide) and Request a license 417.76 (134.24), y 521, ending at 552. View all benefits opens the in-dialog benefits view (Back returns), whose footer has only Buy now + Request a license at 520.67 and content ends at 472.67.
- Gates: Request a license with ECS enableTeamsPremiumLicenseRequest (default true); Buy now with enableTeamsPremiumDTBSelfPurchase and LFT policy isSelfPurchaseAllowed (not DISABLED / ONLY_TRIALS_WITHOUT_PAYMENT_METHOD), link teamsPremiumCenterSelfPurchaseLink.
- Pill (async-entry Wse/Dse/Bnt/Ose): rendered only when Bnt = (enableWebControls||enableMacButtonPlaceholder) && vw>=947 || vw>=1280 (enableWebControls is only for platforms 1454/1415, so Teams desktop on Windows: 1280 CSS px) and after Ose(12e4) (first 120 s); the device marks are written only when it renders. testpc1 (1024 px screen) shows the plain ··· (screenshot 2026-11-27). Not clicked: Request a license / Buy now.
OST: PremiumDialog ended page and benefits footer at Teams' geometry, ECS/policy gates in premium_view (licenseRequest/selfPurchase/selfPurchaseLink); TitleBar pill needs width>=1280 and 120 s; backend keeps pending marks until premiumPillShown(). Harness --premium-pill-test.

Live checks (build of this branch on testpc1, OST under WSLg, ost-test1 profile spatest):
- --premium-test: PREMIUM json mode ended, pill get, licenseRequest true, selfPurchase true (policy ENABLED). The ended page matches Teams' measured geometry and strings (title 257/582 in a 1000x720 window = dialog y 197; Buy now 502, Request a license ends 752 = 552; View all benefits at 224); its benefits view shows only Buy now + Request a license; nothing clicked.
- --premium-pill-test (1000 px window): 75 % zoom (1333 px title bar) before 120 s: hidden; after 120 s: 1000 px hidden, 1250 px hidden, 1333 px "Get Premium" shown. Teams on testpc1 at 1024 px: plain ··· (matches). Not observed live: Teams desktop showing the pill at >= 1280 (testpc1's screen is 1024 wide, winpc keeps the trial end date so never shows it; Teams' zoom/settings were not touched) - the 1280 rule comes from its code.
- Unit tests: api::premium (buy_now_as_teams_policy + existing) pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Get Teams Premium after an ended trial now shows Teams' post-trial page as measured live on winpc, and the title-bar Premium pill follows Teams' width and start-up rule.

Changes:
- PremiumDialog.qml "ended": Teams' strings (keys confirmed, explicit ids for Request a license / Buy now / View all benefits), title/description/feature positions, the reversed footer with View all benefits 79.33 tall at 24,497 and Buy now + Request a license at 521 ending at 552; View all benefits now opens the in-dialog benefits view (Back returns; footer Buy now + Request a license at 520.67, content ends at 472.67).
- Buttons gated as Teams: Request a license by ECS enableTeamsPremiumLicenseRequest, Buy now by enableTeamsPremiumDTBSelfPurchase and the self-serve policy (api::premium::self_purchase_allowed), link from teamsPremiumCenterSelfPurchaseLink (premium_view JSON).
- TitleBar pill: only at >= 1280 px (CSS px, zoom included) and after 120 s; the device marks are saved only once the pill shows (backend.premiumPillShown()).
- Spec docs/spec/settings-and-more.md; harness --premium-pill-test.

Tests: api::premium unit tests; live --premium-test and --premium-pill-test on testpc1. Unverified live: Teams itself showing the pill at >= 1280 px (code-derived).
<!-- SECTION:FINAL_SUMMARY:END -->
