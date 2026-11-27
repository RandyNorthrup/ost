---
id: TASK-0357
title: 'Settings and title bar as Teams: Denoising, About date, ended Premium trial'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-27T17:32:00Z'
updated_date: '2026-11-27T22:47:00Z'
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
- [ ] #1 B-12: Settings > Devices > Video: "Denoising" switch missing, as Teams desktop does it, checked side by side
- [ ] #2 B-14: Settings > About: "last checked" date uses a two-digit year, as Teams desktop does it, checked side by side
- [ ] #3 B-15: Title bar: Teams Premium pill and menu rows for an ended (canceled) Premium trial, as Teams desktop does it, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. B-12: research Teams Denoising in its bundles (setting key, storage, pipeline), add ost_vfx Denoiser + videoDenoising setting, Settings and in-call pane rows.
2. B-14: Teams formats About's date with Intl toLocaleString(undefined,{year,month,day numeric}); add regional::numeric_date (ICU yMd table for every Teams culture, Persian/Buddhist calendars, native digits) and use it.
3. B-15: reverse Teams' TeamsPremiumTitleBar / MoreOptionsMenuItem rule (LFT trial, licence flags, ECS premiumTitleBarConfig, per-device localStorage marks); implement api::premium::entry with tests; rewire backend/TitleBar.
4. Build/test on a build box, live-check on linuxlt as ost-test1 against Teams on testpc1/winpc, PR, CI/Codex green.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Research (MSTeams 26304.1207.5384.858 bundles on testpc1, local storage read-only on winpc/testpc1):

B-12 Denoising: ECS calling.enableVideoDenoising (true for ost-test1) + slimcore isVideoDenoisingCapable gate the row (Settings Devices after Super resolution; in-call pane Advanced settings with Super resolution, before Mirror). Strings calling:kcznlaild "Denoising", calling:k36c8ufd5 (Teams spells "availlable"). Device setting videoDenoisingEnabled (localStorage + app device settings cmd_settings.json, shared by accounts on the device, not roamed); default ON ("Initializing Video Denoising to ON (FF enabled, no stored preference)"). Applied as the camera video filter (slimcore VideoEffectType.Denoising 1048576 via setVideoFilterState), re-applied on camera change, so preview and sent video both carry it.

B-14: Teams About uses lastUpdated.toLocaleString(undefined,{year:"numeric",month:"numeric",day:"numeric"}) (settings-app bundle), i.e. ICU yMd in the app language: en-US 11/27/2026.

B-15: Teams' rule (async-entry dnt/cnt/lnt/rnt, oat/iat/sat/Pst; LFT service): trial = eligibility (403 body: numeric ineligibilityReason -> EXPIRED_LFT/COMMERCE_HARD_BLOCK, entity state -> Pending/Active/Inactive) or entity when licensed; isEnded = EXPIRED_LFT or Inactive with endDate. Menu: ONE row: Get Teams Premium when ended (or local end date passed), Teams Premium benefits in an active trial, Unlock otherwise when eligible; a separate benefits row only with a Premium licence (isTPManagement) not in an active trial. Pill: N days left in a trial (stores TeamsPremiumUserTrialEndDateGlobalEntryPoint); Get Premium after a trial only while post-trial promo active (14 days, ECS premiumTitleBarConfig.postTrialPromoDurationInDays, from first view TeamsPremiumUserFirstViewPostTrialGlobalEntryPoint) and the trial is fetched, which Teams skips when the end date was stored -> so pill only after that date. Verified: winpc localStorage has TrialEndDate ~2027-01-15 (no pill, one row); testpc1 (fresh device, ost-test1) has FirstViewPostTrial 2026-11-27 and SHOWS the Get Premium pill. Licence details for ost-test1 now: isTPManagement false, isTeamsPremiumSelfAssigned false.

Not clicked: Get Teams Premium / Request a license anywhere.

PR #67 opened 2026-11-27 (branch task-0357-settings-titlebar). Live on linuxlt (ost-test1): --premium-test pill get/menu get/benefitsRow false = Teams on testpc1 (fresh device); --about-test 11/27/2026 (en-US) and 27.11.2026 (de_DE); --cards-test Devices rows in Teams' order with Denoising On; --denoise-test on a virtual noisy camera /dev/video23 (no real camera frames saved). Unverified: kept-end-date path (unit tests only), other languages vs Teams, in-call pane row live, quantitative parity with Teams' AI denoiser. Follow-up TASK-0361 (licence-request dialog, pill at narrow widths). Note: testpc1 C: had 307 MB free (WSL I/O errors); cleared its Windows Update download cache and old temp files (3.6 GB free). testpc2 C: was at 0 bytes (vhdx 129.6 GB), only 359 MB could be freed safely; the MacBook VM disk is full.
<!-- SECTION:NOTES:END -->
