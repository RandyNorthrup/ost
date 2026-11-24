---
id: TASK-0149
title: Automatic work location (Privacy) where the tenant allows it, as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-23T08:35:00Z'
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
- [x] #3 With it on, OST sets the work location from the detected place as Teams does
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

- 2026-11-23 (agent wifiM):
  - Allow list: GET {iC3LocationService}/v1/me/ssid-allowlist now returns {"SSIDList":["Condor Cave"]} for ost-test1, ~33 h after the 11-21 setting. It was empty at ~10 h. Nothing in the tenant had been wrong: Get-PlacesSettings -Collection Presence shows WorkplaceWifiNetworkSSIDList Default "Condor Cave" (the 'Default:' prefix is the scope, not part of the value), and Get-PlaceDevice shows BSSID F4:92:BF:78:C4:67 -> OST Test Building. The reply doesn't depend on the client headers (x-ms-client-os linux/windows/mac and both client versions give the same list).
  - Places settings (read only): Places.EnableBuildings, PlacesEnabled, PlacesFinderEnabled and Entitlement are all false. Microsoft's Set-PlacesSettings page says OID (group) scoping works only for PlacesFinderEnabled, and PlacesEnabled can no longer be set. So buildings can't be turned on for the test accounts alone, and they were left off (turning them on tenant-wide would change real users' work-location pickers). Workplace check-in is a Places "core" feature (Business Basic is enough).
  - Tenant change: Entra security group "OST workplace check-in test" (8c63fcbc-9d15-4382-a013-171f0a4897da; ost-test1 and ost-test2) was created for scoped Places settings. It turned out not to be usable for that (see above).
  - Graph Command Line Tools consent: Group.ReadWrite.All and User.Read.All, for Randy only, not org-wide.
  - Working hours: ost-test1's Outlook working hours were Mon-Fri 08:00-17:00 Pacific Standard Time. Set temporarily to every day 00:00-23:59 PST (PATCH /me/mailboxSettings) for the Sunday test; to be put back at the end.
  - Teams (26304 worker): there is no client-side working-hours check; the service applies the working hours. Teams checks out on a non-office network only with ECS places.adlCheckout (unset for ost-test1, so Teams doesn't check out), a non-empty SSID and a VerifiedLocation work location. Ask-mode first run uses GET .../location/wifiNetwork plus a banner (not built).
  - Live on linuxlt (spatest, Condor Cave): OST turned detection on (policy, ECS enableAutoDetectPlaceWifi, switch Enabled), found Condor Cave on the list and reported the BSSID. The same report gives 200 {OST Test Building} most of the time but 404 about one time in three (6 tries with OST's endpoint: 4x 200, 2x 404). OST's own start-up reports happened to get 404 three times out of three. The service side is still settling.
  - Even after 200s, the presence service (getpresence) showed no workLocation for ost-test1 (05:00-05:12 UTC, Sunday 21:00 PT). Either the working-hours change hasn't reached it yet, or a manual set/clear of the work location earlier today blocks check-ins for the rest of the day, as Microsoft documents.

- 2026-11-23 08:00 UTC onward (agent wifiM), AC3 verified live:
  - OST on linuxlt (spatest, Condor Cave), started just after midnight PT: "WORKLOC network change: Building { OST Test Building }". Presence (getpresence, both the classic and the presenceUPS host) then read {location Office, locationSource VerifiedLocation, approximateDetails {id a93350e7-..., idType Directory, name OST Test Building}, isForced true, expiry 2026-11-24T01:00Z = 17:00 PT, maxShared Specific}. OST's flyout shows "In OST Test Building" (harness --pause-test=wl-show, picture wl-show), and so does Teams on winpc (regular building-checkmark icon in #424242; OST now matches).
  - Why Sunday never worked: the 200s on Sunday set nothing. The expiry above is the old Mon-Fri 8-5 working hours, so the service was still using those hours (my all-day change hadn't reached it). Microsoft also documents that a manual set or clear blocks check-ins for the rest of that day.
  - Teams' rules found (26304 ADL job action strategy and worker), now followed by OST (desktop/src/work_location.rs):
    - Flights at Teams' bundled defaults: adlCheckout, adlWiredCheckout, useSSIDForIC3LSNetworkApiRequest (the SSID goes in the report) and useUserStateForWiFiUpdate. OST had read these as off when ECS was silent.
    - Empty allow list: nothing. Listed Wi-Fi: report. Other Wi-Fi: SSID_MISMATCH. Wired and online: WIRED_CONNECTION, kept when the device's stationary building is the checked-in one. Offline: nothing.
    - A check-out is a DELETE, and only from a VerifiedLocation. Nothing happens while the machine is locked.
  - Seen live on winpc: Teams there (wired, Windows location Deny) checked ost-test1 out and showed the banner "Your work location was cleared because your device is no longer connected to Wi-Fi. If this is a stationary device, set a permanent location to prevent this." with Open settings / Don't show again. OST doesn't show that banner yet; nor Teams' Ask-mode first-run banner. Both are follow-ups.
  - The 404 flakiness on reports (about one in three) was still seen before midnight. After midnight OST's reports got 200.
  - The winpc Ethernet-off test of Teams' own Wi-Fi check-in was not run. OST's check-in already showed identically in Teams, and Teams on winpc, being wired with location off, checks out by design. Nothing was changed on winpc for it.
  - Restored: placesSettings autoUpdateLocationPreference back to Disabled; ost-test1 working hours back to Mon-Fri 08:00-17:00 Pacific Standard Time. The checked-in work location expires on its own at 17:00 PT; it was not cleared by hand, which would block check-ins for the day.
  - Tenant: the Entra group "OST workplace check-in test" was deleted again. The Graph CLI consent Group.ReadWrite.All (Randy only) remains.
  - Tests: 917 lib + 30 desktop pass (linuxlt).

- 2026-11-23 merged (8bbadba3, 055819c2). Banners moved to TASK-0249.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Automatic work location (Privacy) as Teams: the card, toggle (placesSettings.autoUpdateLocationPreference) and Learn more dialog where the policy allows it; on each network change OST follows Teams' check-in strategy — the allowed Wi-Fi list (cached a day), reporting the access point and network name, check-out on another Wi-Fi, wired or location-off as Teams' defaults say — and shows the checked-in building in the profile flyout with Teams' icon. Verified live: OST on linuxlt checked ost-test1 in at "OST Test Building" and Teams on winpc showed the same. Test tenant: Places Wi-Fi list "Condor Cave" mapped to OST Test Building. Follow-up TASK-0249.
<!-- SECTION:FINAL_SUMMARY:END -->
