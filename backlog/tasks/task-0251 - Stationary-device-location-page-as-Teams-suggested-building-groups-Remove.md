---
id: TASK-0251
title: Stationary device location page as Teams (suggested building, groups, Remove)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-23T10:07:00Z'
updated_date: '2026-11-23T12:35:00Z'
labels:
  - desktop
  - settings
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-0249: the check-out banner's Open settings opens Settings ▸ Privacy ▸ Stationary device location with the checked-in building as suggestedBuildingId. Teams 26304 (settings-app, DeviceHomeBuildingSettings) lists that building and your current Office work location under a 'Suggested' group above 'All' buildings (only those in the tenant's building list), and shows a Remove button once a building is set; OST's page has one flat list and no Remove.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The stationary page shows Teams' Suggested and All groups, with the banner's suggested building and the current office building, as Teams
- [x] #2 A set stationary building can be removed as in Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams 26304 settings-app DeviceHomeBuildingSettings (b7/k7), the places worker resolvers (placesBuildings, buildingById, getBuildings flight) and Fluent Combobox/OptionGroup/Option/Spinner styles
2. Find what makes Places list buildings for the test accounts without tenant-wide changes (findPlaces vs getBuildings, scoping)
3. api::places: Teams filters (deburr name/city/state/country), getBuildings, building_by_id; unit tests
4. Backend: loadBuildings(suggestedId) with buildingById; own work location building id
5. SettingsView stationary page: spinner, not-found error, Suggested/All groups with icons, Delete button, saving state; launch options
6. Build on linuxlt, tests, verify live as ost-test1 (spatest) and against Teams on winpc; restore settings
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams 26304 (settings-app DeviceHomeBuildingSettings b7/k7, places worker resolvers): list = placesBuildings (findPlaces Type = "Building", or GET v2.0/places/getBuildings with ECS places.enableNewGetBuildingsAPIInMeControl, default off; off for ost-test1); Suggested = buildingById(suggestedBuildingId) (findPlaces Type = "Building" AND Id = "…", exactly one) then presence(ups) Office building if different, only those in the filtered list; search = lodash deburr on name/city/state/country; sort Intl.Collator numeric/base; not-found yellow note; Delete (settings:k77lelyx4 "Delete") writes deviceHomeBuildingId null; Spinner + "Loading..." while loading. Spec: docs/spec/settings.md.
- Tenant: findPlaces, getBuildings and findPlaces-by-id for OST Test Building (a93350e7-f3a6-…) all return empty as ost-test1. Places EnableBuildings is tenant-wide only (Microsoft docs: OID scoping only for PlacesFinderEnabled); Teams reads no other source for this list. Nothing changed in the tenant; built from Teams' code with unit tests (api::places: deburr, collate/sorted, matching, suggested, filters, records) and a --stationary-fixture harness.
- winpc (read-only): Teams' page and its "No buildings found" list match OST's live page (no building set on winpc, nothing changed).
- Live on linuxlt as ost-test1 (spatest): run 1 real tenant with the banner building suggested -> "No buildings found", suggestion hidden (buildingById None), as Teams. Fixture runs: Suggested (OST Test Building, history icon) over All (Annex 9, Annex 10, Headquarters, OST Test Building) with the divider; search "que" -> Annex 10 (Québec); saved unknown id -> yellow note + Delete; pick Headquarters -> saved, note gone; Delete -> cleared, button gone.
- Restored: linuxlt ~/.config/ost/desktop.json deviceHomeBuildingId removed again (was absent). ost-test1 work location untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's Settings ▸ Privacy ▸ Stationary device location now works the way Teams 26304's DeviceHomeBuildingSettings page does.

Changes:
- src/api/places.rs:
  - The list comes from findPlaces, or from `GET v2.0/places/getBuildings` when the ECS flight places.enableNewGetBuildingsAPIInMeControl is on.
  - buildingById (`Type = "Building" AND Id = "…"`, used only when Places returns exactly one).
  - Buildings carry city, state and country, sorted the way Intl.Collator (numeric, base) sorts them.
  - Search uses lodash deburr over name, city, state and country.
  - Teams' Suggested rule.
  - Unit tests for each.
- desktop/src/backend.rs:
  - loadBuildings(suggestedId) and buildingOptions(query, office).
  - myWorkLocationDetail now carries buildingId.
  - `--stationary-fixture` lists a fixture file instead of the tenant's buildings.
- desktop/qml/SettingsView.qml:
  - A spinner with "Loading..." while loading.
  - The yellow "could not be found" note.
  - Suggested (history icon) and All buildings (building icon) as Fluent OptionGroups with a divider; options have the check, a 14 px icon and the name.
  - A search box that clears when the list opens and shows the set building when closed.
  - A Delete button that clears the setting.
  - The check-out banner's suggestedBuildingId reaches the page.
- Main.qml: harness `--stationary-test`.
- New icon history-20; i18n ids regenerated (Teams settings ids); spec in docs/spec/settings.md; docs/desktop.md.

Tenant: Places shows the test tenant no buildings. findPlaces, getBuildings and by-id all return empty. EnableBuildings can only be set tenant-wide, so nothing was changed; the groups were verified with a fixture.

Tests:
- cargo test --features audio,video --lib: 930 ok.
- desktop cargo test: 35 ok.

Live on linuxlt as ost-test1:
- Real tenant: "No buildings found", the same as Teams on winpc.
- Fixture: groups, search, the not-found note, choosing a building and Delete.
- The setting is restored.
<!-- SECTION:FINAL_SUMMARY:END -->
