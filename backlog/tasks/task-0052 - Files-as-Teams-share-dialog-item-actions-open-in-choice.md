---
id: TASK-0052
title: 'Files as Teams: share dialog, item actions, open-in choice'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-12T06:53:00Z'
labels:
  - files
dependencies: []
references:
  - docs/parity/files-apps.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Files P1 gaps (docs/parity/gaps-shell-calendar-files.md, docs/parity/files-apps.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Share dialog (copy link, link settings, recipients, permissions, message, Send) as Teams, via Graph
- [x] #2 More actions: Rename, Move to, Copy to, Copy link, Open in …, Open in OneDrive
- [x] #3 Office files open per Teams' 'Always open … in' setting (desktop app / browser natively)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11: AC#1 done (2295a1b). Teams opens OneDrive's own share dialog (sharedialog.aspx, clientId=teams); OST draws it natively over the same SharePoint REST methods (GetSharingInformation, ClientPeoplePickerSearchUser, ShareObject, ShareLink, UpdateDocumentSharingInfo, UnshareLink, UnshareObject) with a SharePoint token from the refresh token, not Graph (Graph has no equivalent of the dialog's defaults or existing-access links). Spec: docs/spec/onedrive-share.md.
- Verified: every view measured on winpc; live Send to OST Test 2 + Stop sharing on ost-share-test.txt (OST Test 1's OneDrive); Teams-side captures of create/delete org link and role change/remove on ost-attachment-test.txt, all reverted.
- Entry points so far: channel Files' Share (folder). Left for AC#2: per-item Share / Manage access in the OneDrive view and channel Files rows (Teams' context menu: Open, Preview, Share, Copy link, Manage access, Delete, Add to favorites, Add shortcut, Download, Rename, Open in OneDrive, Move to, Copy to, Duplicate), and the Files variant's ··· "Send link in Outlook".
- Not yet seen in Teams: the People-you-choose link body and the organisation / specific-people wording in Access summary.

- 2026-11-11: AC#2 done. Teams' Files menu captured on winpc (OneDrive's Fabric context menu: 16 items for a file, folder and video variants, Open ▸ / Add shortcut ▸ submenus), Rename / Delete? dialogs, Copy link's "Link created" / "Link copied", the Move to / Copy to picker and the notices (docs/spec/file-actions.md).
- OST: desktop/qml/FileActions.qml, used by OneDriveView and ChannelFiles (right-click and ···); MenuPopup `fabric` mode. Copy, move and Duplicate use SharePoint's copy jobs as Teams does (CreateCopyJobs / GetCopyJobProgress, src/api/copy_jobs.rs); Rename uses Graph; Open in app opens a cached copy with the desktop's app.
- Live-tested with --file-actions-test --file-actions-live --file-actions-link on ost-share-test.txt: duplicate (copy deleted), rename and back, copy to Attachments (copy deleted), move there and back, Copy link (the Anyone link deleted afterwards). Teams-side captures were undone (rename back, link and duplicate deleted).
- Follow-ups: TASK-0115 (Preview, Version history, Details), TASK-0116 (Add shortcut, Request files, Folder color, folder Download, Add to playlist), TASK-0117 (picker places, search, new folder, Suggested names), TASK-0118 (OneDrive rows as Teams).

- 2026-11-11: AC#3 done. Teams' setting on winpc offers Teams / Browser (synced fileOpenPreference teamsV2 / web) and adds a device-only Desktop app with Office installed; Teams is moving files to the desktop app. OST offers Desktop app (the desktop's app for Word files, from xdg-mime or the MIME cache; device setting fileOpenIn, default when present) and Browser. Teams' in-window Office for the web is not embedded (no web views).
- Backend::open_file now opens files from the OneDrive view, channel Files, chat file cards and search: Office files with Desktop app chosen are downloaded to ~/.cache/ost/open and opened with that app; everything else goes to the browser.
- Verified on linuxlt with --open-file-test on a disposable ost-open-test.docx (OST Test 1's My files) and a logging stand-in app registered for .docx (removed afterwards, mimeapps restored): both the drive-item and by-address paths handed the downloaded copy to the app. Follow-up: TASK-0119 (the page's ask-where-to-save toggle and web links browser).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Files in OST now work as Teams' Files apps do for sharing, item actions and opening Office files.

Changes:
- AC#1 (2295a1b): OneDrive's share dialog drawn natively over SharePoint's sharing REST methods (OneDriveShare.qml, src/api/sharing.rs; docs/spec/onedrive-share.md).
- AC#2 (17d4318): Teams' Files context menu (right-click / ···) in the OneDrive app and channel Files with Open ▸, Share, Copy link ("Link created" / "Link copied"), Manage access, Delete?, favorites, Download, Rename, Open in OneDrive, Move to / Copy to (picker), Duplicate and OneDrive's notices (FileActions.qml, MenuPopup fabric mode). Copy, move and Duplicate use SharePoint copy jobs as Teams does (src/api/copy_jobs.rs).
- AC#3: Settings ▸ Files and links offers Desktop app (the desktop's app for Word files) and Browser; Backend::open_file applies it wherever files open (OneDrive, channel Files, chat file cards, search).

Tests:
- cargo test --lib (copy job bodies, duplicate names, progress errors, folder addresses).
- Live harnesses on OST Test 1's files: --share-test, --file-actions-test --file-actions-live --file-actions-link, --open-file-test; every change undone.

Follow-ups: TASK-0115..0119 (Preview / Version history / Details, menu extras, picker places, OneDrive rows, Files and links extras).
<!-- SECTION:FINAL_SUMMARY:END -->
