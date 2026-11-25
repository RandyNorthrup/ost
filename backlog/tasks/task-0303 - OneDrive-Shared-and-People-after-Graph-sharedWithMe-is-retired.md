---
id: TASK-0303
title: OneDrive Shared and People after Graph sharedWithMe is retired
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T15:49:00Z'
updated_date: '2026-11-25T18:34:00Z'
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
- [ ] #1 OST's OneDrive Shared view and Browse files by People keep working without /me/drive/sharedWithMe, with the same items and order Teams shows
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
<!-- SECTION:NOTES:END -->
