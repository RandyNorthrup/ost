---
id: TASK-0149
title: Automatic work location (Privacy) where the tenant allows it, as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-21T19:20:00Z'
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

- 2026-11-21 (agent setF) Tenant changes (authorized by the user via the coordinator):
  - Places setting Presence.WorkplaceWifiNetworkSSIDList = 'Default:Condor Cave' (linuxlt's Wi-Fi; tenant-wide by design, only users with the work-location detection policy — the test accounts — use it).
  - Places Wi-Fi device: linuxlt's access point BSSID mapped to OST Test Building (Add-WifiDevices UploadEntries; device a29c1b98-1184-4db5-b9a1-bb22637bc298, place a93350e7-…). Places.EnableBuildings left off (tenant-wide).
  - How (the module's password prompt avoided): MicrosoftPlaces 2.1.13 on winpc (pwsh 7, installed to Documents\PowerShell\Modules, PSGallery marked trusted, msalruntime.dll added), with a device-code token for the module's own app (PlacesCmdletModule 05c7489d-…, resource outlook.office365.com, approved in Chrome as Randy) injected as the module's ManualAccessTokenProvider (CmdletSession.AccessTokenProvider) before Connect-MicrosoftPlaces. Token file deleted from winpc.

- 2026-11-21 live check on linuxlt (ost-test1, Wi-Fi Condor Cave): OST turned detection on with the policy and switch, read the network from NetworkManager and asked the location service; the SSID allow list still came back empty ~30 min after the change (Places says up to 12 h for settings, 24–48 h for BSSIDs), so it correctly treated the network as not an office network. Next check: once the list has "Condor Cave", run with RUST_LOG=warn,ost_desktop::work_location=info and --setf-test --setf-worklocation during ost-test1's working hours (Mon–Fri 8–5 PT); expect "WORKLOC network change: Building { name: OST Test Building }" and the work location in the profile flyout.

- 2026-11-21 (agent setH) re-checked ~10 h after the Places Wi-Fi change: GET {iC3LocationService}/v1/me/ssid-allowlist (examples/ic3_location, OST Test 2, who has the same work-location policy) still returns 0 entries. linuxlt is on Condor Cave (BSSID F4:92:BF:78:C4:67, the one mapped to OST Test Building), so the setting hasn't reached the location service yet (Places says up to 12 h for settings, 24–48 h for BSSIDs). Today is Saturday, outside ost-test1's working hours, so a check-in couldn't happen anyway. Next: a weekday 8–5 PT, once the list has 'Condor Cave'; run --setf-test --setf-worklocation with RUST_LOG=warn,ost_desktop::work_location=info.
<!-- SECTION:NOTES:END -->
