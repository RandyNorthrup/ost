---
id: TASK-0052
title: 'Files as Teams: share dialog, item actions, open-in choice'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-12T06:37:00Z'
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
- [ ] #3 Office files open per Teams' 'Always open … in' setting (desktop app / browser natively)
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
<!-- SECTION:NOTES:END -->
