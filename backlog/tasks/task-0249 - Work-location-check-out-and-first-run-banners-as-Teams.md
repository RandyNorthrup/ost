---
id: TASK-0249
title: Work location check-out and first-run banners as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-23T08:35:00Z'
updated_date: '2026-11-23T10:33:00Z'
labels:
  - desktop
  - settings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0149: Teams shows a banner when it clears the work location because the device left Wi-Fi ('Your work location was cleared because your device is no longer connected to Wi-Fi…'), and a first-run banner for users who never set the automatic work location switch; OST shows neither.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST shows Teams' check-out banner when it clears a checked-in work location
- [x] #2 OST shows Teams' first-run banner for users who never set the switch, as Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 banner code (worker notification helper, pre-warm banner jobs, async-apps-places handlers, shell MessageBar, griffel CSS)
2. work_location.rs: modes off/ask/on, first-run look-up (GET wifiNetwork), check-out banner rule; backend signal
3. Main.qml: mode, Location banner, state, actions, dialog, toast; harness --wl-banner-test/show
4. Verify live on linuxlt (spatest) with a dummy NM primary connection as "wired"; restore
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams 26304: worker emits placesNotificationEvent (ADL_FIRST_RUN_BANNER / ADL_DEVICE_HOME_BANNER / OS consent / inform); front end PlacesAutoDetectLocationBannersJob shows a shell MessageBar (intent Location, LocationLive filled icon, title semibold + space, text, link 4px on, button, X) only with ECS places.enableAutoDetectLocationBanners (on for the tenant). Details in docs/spec/settings.md "Work location banners".
- Check-out banner: only WIRED_CONNECTION check-outs that were reported, device without stationary building; state deviceHomeBannerState (max 3, once a day, cooldown 0, 600 s); Open settings -> OPEN_SETTINGS + Stationary page, Don't show again -> DONT_SHOW_AGAIN; X keeps nothing. SSID_MISMATCH raises no banner.
- First-run: listed Wi-Fi, not consented, not acknowledged (FIRST_RUN/SETTING_TOGGLE), never seen; GET .../location/wifiNetwork?bssid&ssid (no check-in); writes autoLocationFirstRunBannerLastIncrementDate; Tell me more -> dialog; button/dialog Set -> FIRST_RUN + Enabled + toast "Automatically setting your location has been enabled." (Settings); X/Not now -> FIRST_RUN.
- ost-test1 policy userSettingsDefault Disabled, so a never-set switch is Ask mode.
- Live on linuxlt 2026-11-23 10:00-10:07 UTC (placesSettings reset to {} for the run): Ask -> look-up named OST Test Building -> first-run banner -> Tell me more -> dialog -> Set -> toast, switch Enabled, check-in (presence Office/VerifiedLocation at 02:01 PT, outside working hours). NM primary switched to a dummy connection (traffic kept on Wi-Fi via policy routing) -> WIRED_CONNECTION check-out -> check-out banner -> Open settings -> Stationary device location; presence cleared ~56 s later; next wired check-out: banner not eligible (dismissed). Second run: button path (Set my location automatically) and Don't show again verified.
- Restored: placesSettings back to {SETTING_TOGGLE, Disabled}; NM dummy connection, ip rules and table 100 removed; local placesDeviceHomeBannerState removed. ost-test1 is left checked in at OST Test Building by the last automatic Wi-Fi report (expires on its own; not cleared by hand).
- Follow-up TASK-0251 (Stationary page suggested/All groups, Remove).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST now shows Teams' two work location banners from the Wi-Fi check-in, as Teams 26304 does.

Changes:
- desktop/src/work_location.rs: modes off/ask/on. Ask (switch never set: not consented, never answered, first-run banner not seen) only looks the office network up (GET .../location/wifiNetwork?bssid&ssid, api::places::resolve_network) and raises the first-run banner; check-outs need consent; a reported wired check-out on a device with no stationary building raises the check-out banner. Banners reach QML through Backend::work_location_banner.
- Main.qml: workLocationMode (Teams' consent rule incl. FIRST_RUN), the shell banner intent Location (LocationLive filled icon, semibold title, text, link, button, X, wraps), the check-out banner's eligibility state (max 3, once a day, Open settings / Don't show again end it) and the first-run banner (seen date, Tell me more dialog, Set my location automatically: FIRST_RUN + Enabled + toast; X/Not now: FIRST_RUN); ECS places.enableAutoDetectLocationBanners gates both. Harness --wl-banner-test / --wl-banner-show.
- examples/user_properties --set; spec docs/spec/settings.md "Work location banners"; docs/desktop.md.

Tests: cargo test --features audio,video --lib (919 ok), desktop cargo test (35 ok, incl. new checkout_banner and places query tests).
Live (linuxlt, ost-test1): first-run banner -> dialog -> opt-in toast and check-in; wired (dummy NM primary) check-out -> check-out banner -> Open settings; Don't show again and the button path in a second run; settings and network restored.
Follow-up: TASK-0251.
<!-- SECTION:FINAL_SUMMARY:END -->
