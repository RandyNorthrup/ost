---
id: TASK-0149
title: Automatic work location (Privacy) where the tenant allows it, as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-21T07:55:00Z'
labels:
  - settings
  - presence
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the tenant's work-location detection policy is on (ECS places.enableWorkLocationDetectionPolicy with enableAutoDetectPlaceWifi), Teams' 'Manage my work location' card has a toggle to update the work location automatically from the office Wi-Fi/peripherals (userPreferences placesSettings.autoUpdateLocationPreference), with a Learn more dialog. The scnetsolutions tenant has the policy off, so OST shows Teams' 'turned off by your IT department' text and the Outlook link; this task covers the policy-on case.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With the policy on, the card shows Teams' automatic work location toggle and Learn more dialog
- [x] #2 The toggle is saved where Teams keeps it (placesSettings.autoUpdateLocationPreference)
- [ ] #3 With it on, OST sets the work location from the detected place as Teams does
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-15 tenant (user: "you are authorized to adjust anything in the test tenant to unblock us"): TeamsWorkLocationDetectionPolicy 'OST test accounts' (EnableWorkLocationDetection true) created with Teams PowerShell and granted to ost-test1 and ost-test2 only (Global stays off).

- 2026-11-15: built and checked against Teams on winpc.
  - Teams maps teamsWorkLocationDetectionPolicy (effective policies) onto places.enableWorkLocationDetectionPolicy. OST reads it at sign-in (backend.workLocationPolicyJson; api::custom_emoji::effective_policies).
  - The policy-on card: switch, "Learn about automatically setting a work location", "Manage stationary location", Outlook note. The card is 185.16 tall (Teams 185.2), the button at 86.9 (Teams 86.9), links not underlined.
  - Dialog "Why set my work location automatically?" with Teams' picture (assets/illustrations/work-location-auto.png). Off: Not now / Set my location automatically. On: Got it.
  - The switch is the user property placesSettings.autoUpdateLocationPreference, now parsed as JSON. Turning it off from OST showed Off in Teams on winpc.
  - Privacy ▸ Stationary device location: buildings from Places (middle tier v2.0/places/findPlaces, api::places), "No buildings found" as Teams. The choice is device-local.
  - "OST Test Building" was created with Graph (beta POST /places), but findPlaces still returns none (Places sync).
  - Left (AC3): detecting the office from Wi-Fi or peripherals and setting the work location (Teams' placesSsidAllowList, reportPlacesDetectedNetwork, attemptAutoDetectLocationOptIn). Needs the tenant's Places networks set up.
  - Harness: --work-location-test [--work-location-off].

- 2026-11-20 (agent setF) AC3 client side built as Teams does it (Teams 26304 worker: PlacesManager/wifiAutoLocationHelper/IC3 location service; docs/spec/settings.md "Workplace check-in over Wi-Fi"): with the policy + places.enableAutoDetectPlaceWifi and the switch on (Main.qml workLocationAuto), desktop/src/work_location.rs reads the Wi-Fi network from NetworkManager over D-Bus (wired ignored) and on each change gets the tenant's SSID allow list (GET {iC3LocationService}/v1/me/ssid-allowlist, cached a day), reports a listed network (PUT …/endpoints/{epid}/location/network {bssid, eventTime, shouldUpdate, canShareLocationDetails}: 200 building, 207 In the office, 404 none) and checks out on other networks (DELETE …/location/wifiNetwork). api::places (tested), examples/ic3_location.
- Live on linuxlt (ost-test1, Wi-Fi): the service answers (needs Teams' MS-CV form); the tenant's allow list is empty (0 SSIDs), so linuxlt's network is not an office network and nothing is checked in; a fake BSSID report gives 404. Open: the tenant's Wi-Fi setup — Set-PlacesSettings -Collection Presence -WorkplaceWifiNetworkSSIDList and Add-WifiDevices (BSSID→building), both in the MicrosoftPlaces module, which needs Windows and an interactive password sign-in (not done; see memory work-location-places), then 24–48 h to propagate and a check-in only within working hours.
<!-- SECTION:NOTES:END -->
