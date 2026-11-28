---
id: TASK-0300
title: 'Personal accounts: files in chats and personal OneDrive'
status: In Progress
assignee:
  - '@tperF'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T08:13:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0293
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Files sent in personal-account chats go to the Microsoft Teams Chat Files folder of the sender's personal OneDrive (5 GB free; photos and videos don't count). There is no Files app for personal accounts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sending and opening files and photos in chats works as in Teams for personal use, stored where Teams stores them
- [x] #2 The chat's Files tab and the storage-full message match Teams
- [x] #3 A personal account's chats have Teams' Photos tab (the gallery of the chat's pictures), next to Chat and Files (TASK-0293 shows Chat and Files only)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams free on teams.live.com (OST Personal 1 and 2 in my own headless Chromes on linuxlt, CDP network log, tokens redacted): upload, send, attach media, attach cloud files, open/download, Files tab, Photos tab, picker; find the storage-full banner in the web client bundles.
2. Engine (src/api/personal_files.rs): Teams free's upload record and createLink (anyone edit), personalFileSite, AMS preview for pictures (sharingMode Attached, amsreferences), cloud reference record, Download by redeeming the link, msgsearch queries for Files and Photos, OneDrive picker places, storage-full detection.
3. UI: Chat/Files/Photos tabs, PersonalFilesTab, PersonalPhotosTab, Teams free's file chip and picture preview in messages, its card menu, compose chip, Attach media as files, two-item Attach menu, PersonalCloudPicker, compose storage-full banner.
4. Live-check in OST with Personal 2 on testpc2 against Personal 1 on teams.live.com; delete test files afterwards.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-28 (tperF) Captured Teams free on teams.live.com as OST Personal 1 and 2 (own headless Chromes on linuxlt, CDP network log, tokens redacted), sending small test files between them: upload (Graph PUT to Microsoft Teams Chat Files, personalFileSite), pictures also into the media store (pish/image, sharingMode Attached; filePreview + amsreferences), send (createLink {"type":"edit"} -> anonymous edit link; the files record), Attach cloud files (OneDrive's consumer picker; createLink on the drive item; a reference record), opening (the link in the browser), Download (shares + prefer redeemSharingLink), Files tab and Photos tab (msgsearch.skype.com v3 queries, 50 files / 5 photos at a time, AMS img_thumb_small tiles), empty states (illustrations/v2 folder-files and photos) and the storage-full banner (web client bundles: SpQuotaReached from HTTP 507 / quotaLimitReached -> "Attachment storage is full", Manage, Get more storage). Details: docs/research/personal-accounts-protocol.md §10.
- Side effects on the test accounts: Graph GET /me/drive/special/cameraroll made an empty "Camera Roll" folder in OST Personal 2's Pictures (to delete at the end).

- Built (src/api/personal_files.rs + QML): Teams free's upload record with createLink and personalFileSite; picture previews in the media store (sharingMode Attached) with filePreview and amsreferences; Attach cloud files through a native OneDrive picker (PersonalCloudPicker: My files with folders, Recent, Photos = the Pictures folder, Shared; Graph) and a reference record; Teams free's two-item Attach menu, compose chips ("Anyone with the link can edit"), Attach media sending pictures as files; received files as Teams free's 48 px chip (···: Open in Browser, Download, Copy link; click opens the link in the browser) and pictures as the picture (fitted to 180 tall, smaller ones in a 180 x 180 box; click opens the picture viewer), files side by side; Download redeems the link (prefer: redeemSharingLink) and fetches the pre-authorised address; Chat/Files/Photos tabs: PersonalFilesTab (msgsearch, Upload, Name/Shared on/Sent by, row menu, selection bar, empty state) and PersonalPhotosTab (msgsearch 5 at a time, day groups, 240 x 200 thumbnail tiles, viewer); the storage-full compose banner (HTTP 507 / quotaLimitReached). Harness: --personal-files-test=<chat> [--personal-send=<paths>] [--personal-cloud=<name>].
- Live (OST Personal 2 in OST on testpc2, build of this branch with OST_QML_DIR, beside OST Personal 1 on teams.live.com): OST sent a text file and a 400 x 300 PNG in one message (Chat Files upload, anyone link, media store preview) and a cloud file from My files > Microsoft Teams Chat Files; Teams free (Personal 1) showed the file chip and the picture, its link opened the file on onedrive.live.com; OST showed Personal 1's files and pictures as Teams free does, its ··· menu, Download saved Personal 1's file with the right content, the Files tab listed all 7 files with sender and time, the Photos tab the 3 pictures under their day, a tile opened the picture viewer; the storage-full banner was drawn (forced in the harness).
- Seen during the checks: the chat service once refused a message with HTTP 403 errorCode 209 SpamMessageDetected (a cloud file re-sent minutes after the same file's upload; Teams' own record shape gave the same answer from a script), and Personal 1's copy of the 1:1 went back to inQuarantine (hidden, no Requests row); re-adding Personal 2 to Personal 1's contacts (managebuddies, as Teams free's Accept does) brought it back. The retry later went through.
- Not verified live: a really full OneDrive (5 GB free; the banner and its trigger are unit-tested and drawn in the harness), files in a group chat, the Files tab's Upload button (it sends like the compose box), videos through Attach media (sent as files without a preview; Teams' handling of videos not captured).
<!-- SECTION:NOTES:END -->
