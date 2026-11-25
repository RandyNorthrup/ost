---
id: TASK-0301
title: OneDrive Recent after Graph drive/recent is retired
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-25T18:23:00Z'
labels:
  - personal-accounts
dependencies: []
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Microsoft stops returning data from Graph /me/drive/recent after November 2026. OST's OneDrive and file picker use it for work accounts today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's Recent files lists (OneDrive, file pickers, Files) keep working without /me/drive/recent, with the same items Teams shows
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research: Graph changelog/docs name no 1:1 replacement (drive/recent and drive/sharedWithMe both degrade until Nov 2026, then return nothing). Capture what Teams desktop's OneDrive app Home calls on winpc (CDP, read only).
2. Read OneDrive's own Home filter (isInvalidOdbRecentItem) and opened-time rule from its bundles, so OST lists the same items in the same order.
3. Add one shared recent-files module over SharePoint sp.RecentFileCollection.DeltaSync with that rule; use it in OneDrive Home (drive::recent, Graph ids resolved per item for the row actions), the cloud picker Home and Attach (cloud_attach::recent), and the share tray fallback (live_share::recent_docs).
4. Fill Home's Opened column from the opened time, its Activity from the recent service.
5. Unit tests from the captured reply; cargo test (root --lib, desktop); live check on linuxlt as ost-test1 vs Teams on winpc.
6. Docs (parity/spec notes), follow-up task for sharedWithMe.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Graph docs: drive/recent (and drive/sharedWithMe) "degraded until November 2026, then stops returning data"; no Graph replacement named (a Tech Community answer suggests Search, unofficial).
- winpc capture 2026-11-25: Teams' OneDrive app Home (filebrowser.aspx?app=TeamsFile, entry oneDrive.recent) calls SharePoint `{personal}/_api/sp.RecentFileCollection.DeltaSync?top=500[&startDateTime=…]` and `GetRecommendations` (For you cards); never Graph. The cloud picker (FilePicker.aspx) Home lists the identical 13 rows.
- OneDrive's filter read from its bundles (isInvalidOdbRecentItem + isInvalidRecentItem + isInvalidODBItem): hidden, deleted empty copies, facet not Present, never opened (UserRelationship or ClientAccessByMailboxOwner LastAccessDateTime), folders other than OneNote notebooks, images, classic attachments, other sources, missing title, RaaS, ics/eml/aspx. Applied to ost-test1's 67 entries it gives Teams' 13 rows in Teams' order.
- Activity: type 2 (RecentlyOpen) is not shown; icons from OneDrive's ActivityType→glyph map. Place line: My Files / "{0}'s Files" / site title.
- Follow-ups: TASK-0303 (sharedWithMe), TASK-0304 (Home layout); personal accounts stay with TASK-0300.

- Live on linuxlt (OST_PROFILE=spatest, ost-test1), 2026-11-25: --onedrive-home-test lists the same 13 rows as Teams' OneDrive Home on winpc, same order, Opened/Owner/Activity text and icons; every row has Graph ids (Graph `/sites/{host},{site},{web}/lists/{list}/items/{n}/driveItem` via $batch). --attach-test's cloud picker Home shows the same 13 (stopped before attaching).
- Tests: root `cargo test --features audio,video --lib` 974 passed; desktop `cargo test` 38 passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OST's recent-files lists no longer use Graph `/me/drive/recent`, which Microsoft retires after November 2026 with no Graph replacement. They now use the service Teams itself calls, SharePoint's recent files service on your OneDrive site (`_api/sp.RecentFileCollection.DeltaSync?top=500`, captured from Teams' OneDrive app and cloud picker on winpc). OST also applies OneDrive's own Home filter, so it lists the same items in the same order Teams does.

Changes:
- New `src/api/recent_files.rs`:
  - Parses the DeltaSync reply.
  - Applies OneDrive's `isInvalidOdbRecentItem` rule, read from its bundles. It leaves out hidden, deleted, partial and never-opened entries, folders other than OneNote notebooks, images, classic attachments, other sources and ics/eml/aspx files.
  - Gets the opened time from UserRelationship, else ClientAccessByMailboxOwner.
  - Words the rows as Teams does: the name without its extension, the place line (My Files / "{0}'s Files" / site), Owner, and Activity with OneDrive's ActivityType glyphs ("recently opened" is not shown).
  - Resolves Graph ids for row actions with one Graph `$batch` (`/sites/{host},{site},{web}/lists/{list}/items/{n}/driveItem`).
- `drive::recent` (OneDrive Home): the backend sends Home rows with Opened, Owner and Activity from the service. The OneDriveView Owner column and title are used for Home.
- `cloud_attach::parse_recent` (cloud picker Home and Attach) uses the same rule. The picker now shows titles, place lines and activity icons as Teams does.
- `live_share::recent_docs` (share tray fallback when Office's MRU fails) uses the same service, filtered by extension, with Graph ids for Excel Live.
- New read-only harness `--onedrive-home-test [--shots=]`.
- Docs: parity/files-apps, spec/onedrive-rows, research/personal-accounts-protocol.

Tests:
- Root `cargo test -j 4 --features audio,video --lib`: 974 passed (new recent_files tests built from the captured reply; updated cloud_attach test).
- Desktop `cargo test`: 38 passed.
- Live on linuxlt as ost-test1: Home and the cloud picker list the same 13 files as Teams on winpc, in the same order and with the same columns; every row has Graph ids.

Follow-ups: TASK-0303 (Graph sharedWithMe is retired too: Shared and People views), TASK-0304 (Home layout: For you cards, filter pills, place line). Personal accounts have no SharePoint and stay with TASK-0300. The share tray fallback was not exercised live, since Office's MRU answered.
<!-- SECTION:FINAL_SUMMARY:END -->
