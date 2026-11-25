---
id: TASK-0303
title: OneDrive Shared and People after Graph sharedWithMe is retired
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T15:49:00Z'
updated_date: '2026-11-25T22:17:00Z'
labels:
  - onedrive
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Microsoft's Graph /me/drive/sharedWithMe is deprecated like drive/recent: it degrades until November 2026 and then stops returning data. OST's OneDrive Shared view and Browse by People (src/api/drive.rs shared_with_me, by_people) still call it. Teams' OneDrive app reads shared files from OneDrive's own services; capture which on winpc and move OST to it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's OneDrive Shared view and Browse files by People keep working without /me/drive/sharedWithMe, with the same items and order Teams shows
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture on winpc (CDP, read only) what Teams' OneDrive app (Shared, People, a person) and the cloud picker (Shared, People) call; read OneDrive's SharedWithMeDataManager / PeopleDataManager rules from its bundles.
2. New src/api/shared_files.rs: the recent files service's DeltaSync (shared with recent_files) + GetSharedWithMeItems(folder) + external items, OneDrive's isInvalidSWMItem / removed / hidden / not-shared-by-you rules, Date shared order; People grouping (sharer + sharing history, collaborator order) and the per-person list (filterByPerson, per-person date).
3. Graph ids per row through recent_files::graph_items ($batch), as TASK-0301.
4. Use it in drive::shared_with_me / by_people callers: OneDrive Shared + People, Move/Copy picker places, cloud picker Shared + People; rows worded (Date shared, Shared by, Activity).
5. Unit tests from the captured reply; cargo test root + desktop, clippy/fmt; live check on linuxlt vs Teams on winpc.
6. Docs (parity/files-apps, spec/onedrive-rows, file-actions).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc capture 2026-11-25 (CDP, read only): Teams' OneDrive app Shared ("With you"), Browse by People and a person's page, and the cloud picker's Shared with you / People, never call Graph. They read the recent files service (`sp.RecentFileCollection.DeltaSync?top=500`, OneDrive maps SharedWithMe/People/Meetings to it), `sp.SharedWithMeItemCollection.GetSharedWithMeItems?top=500&fileType='folder'` (shared folders), `GetSharedWithMeExternalItems` (404 on this tenant) and, for People's order, `sp.PeopleCollection.GetCollaboratorsAsStream?top=100`. By you is `_api/web/onedriveshareditems?$top=1000` (OST has no By you tab).
- OneDrive's rules (SharedWithMeDataManager, isInvalidSWMItem, swmFilterHelper, PeopleDataManager): needs ItemProperties.Shared.LastSharedWithMailboxOwnerDateTime, a Visualization type (not lists), SharePoint ids, ext not ics/eml/aspx/zip, plus isInvalidODBItem; drops facet other than Present/Partial, HiddenFromSharedWithMe, and files you shared yourself (LastSharedById and owner are you). Order: UserRelationship.LastSharedDateTime newest first. Shared by = LastSharedWithMailboxOwnerByDisplayName.
- People rows: each sharer (LastSharedById, plus SharingHistory instances), not you, files newest shared first, people in GetCollaborators order. A person's page also lists files that person owns (filterByPerson) with per-person dates.
- Simulated on ost-test1's reply: With you = Teams' 8 rows in Teams' order; People = OST Test 2 (4 files) then OST Test 3 (2); OST Test 2's page = 7 files as Teams shows.

- Implemented src/api/shared_files.rs (merge of DeltaSync + external + hidden + shared folders, isInvalidSWMItem, With you, People, a person's page, rows with Graph ids via recent_files::graph_items). Removed the Graph callers (drive::by_people over sharedWithMe, cloud_attach::collaborators/order_people, drive::item_title). Picker chips now take the service's Visualization title.
- Live on linuxlt (OST_PROFILE=spatest, ost-test1), 2026-11-25, harness --shared-files-test: Shared lists Teams' 8 rows in Teams' order with the same Date shared / Shared by / Activity; People = OST Test 2 (4 files: release notes, r3 town hall, webinar, ost-share-test) then OST Test 3 (2); OST Test 2's page = Teams' 7 rows in order; the cloud picker's Shared with you and People match Teams' picker. Every row has Graph ids.
- CI checks on linuxlt: cargo fmt --all --check ok (also fixed main's unformatted recent_files::graph_path), cargo clippy --locked --workspace --all-targets -- -D warnings ok, root lib tests 984 passed, desktop 38 passed.
- Follow-up TASK-0320 (By you tab, filter pills, People chips, Shared's columns).

- Correction: main got the rustfmt fix for recent_files::graph_path itself (3d965d05); after the rebase this branch has no change there.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's OneDrive Shared view and Browse files by People no longer use Graph `/me/drive/sharedWithMe`, which Microsoft retires after November 2026. They now read what Teams' OneDrive app and cloud picker read (captured on winpc). That is the recent files service on your OneDrive's site (`sp.RecentFileCollection.DeltaSync`; OneDrive maps its SharedWithMe, People and Meetings views to it), plus the folders shared with you (`sp.SharedWithMeItemCollection.GetSharedWithMeItems?fileType='folder'`), external files (`GetSharedWithMeExternalItems`), and your collaborators' order for People (`sp.PeopleCollection.GetCollaboratorsAsStream`). OST applies OneDrive's own rules, so it lists the same items in the same order.

Changes:
- New `src/api/shared_files.rs`:
  - Merges the replies as OneDrive's item store does.
  - Applies `isInvalidSWMItem` (with `isInvalidODBItem`, now shared with recent_files): it needs a share date, SharePoint ids and a type, and leaves out lists, ics/eml/aspx/zip and removed files.
  - With you: leaves out hidden files and files you shared yourself, newest shared first.
  - People: grouped by sharer and sharing history, without you, in collaborator order.
  - A person's page: adds the files they own, with per-person Date shared and Shared by.
  - Rows have Date shared, Shared by and Activity, plus Graph ids from one $batch per 20 for the row actions.
- `drive::shared_with_me` and `drive::by_people` use it. Their callers are OneDrive Shared and People, the Move/Copy picker's Shared and People (folders only), and the cloud picker's Shared with you and People (chips named by the service's title).
- Removed the Graph-based helpers (`cloud_attach::collaborators`/`order_people`, `drive::item_title`).
- OneDriveView: Shared and a person's page now head their columns Date shared and Shared by, an empty Shared by stays empty, and the People count comes from the row's files.
- New read-only harness `--shared-files-test [--shots=]`.
- Docs: parity/files-apps, spec/onedrive-rows, spec/file-actions.

Tests:
- Unit tests built from the captured reply: shared_files (4).
- On linuxlt: `cargo fmt --all --check` ok, `cargo clippy --locked --workspace --all-targets -- -D warnings` ok, root lib 984 passed, desktop 38 passed.
- Live as ost-test1: Shared shows the same 8 rows as Teams on winpc, in the same order. People shows OST Test 2 (4 files), then OST Test 3 (2). OST Test 2's page shows the same 7 rows. The cloud picker matches Teams' picker.

Follow-up: TASK-0320 covers the By you tab, filter pills, People chips and Shared's columns. Personal accounts stay with TASK-0300.
<!-- SECTION:FINAL_SUMMARY:END -->
