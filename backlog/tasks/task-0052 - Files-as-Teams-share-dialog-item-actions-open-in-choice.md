---
id: TASK-0052
title: 'Files as Teams: share dialog, item actions, open-in choice'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T03:57:00Z'
updated_date: '2026-11-12T04:59:00Z'
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
- [ ] #2 More actions: Rename, Move to, Copy to, Copy link, Open in …, Open in OneDrive
- [ ] #3 Office files open per Teams' 'Always open … in' setting (desktop app / browser natively)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11: AC#1 done (2295a1b). Teams opens OneDrive's own share dialog (sharedialog.aspx, clientId=teams); OST draws it natively over the same SharePoint REST methods (GetSharingInformation, ClientPeoplePickerSearchUser, ShareObject, ShareLink, UpdateDocumentSharingInfo, UnshareLink, UnshareObject) with a SharePoint token from the refresh token, not Graph (Graph has no equivalent of the dialog's defaults or existing-access links). Spec: docs/spec/onedrive-share.md.
- Verified: every view measured on winpc; live Send to OST Test 2 + Stop sharing on ost-share-test.txt (OST Test 1's OneDrive); Teams-side captures of create/delete org link and role change/remove on ost-attachment-test.txt, all reverted.
- Entry points so far: channel Files' Share (folder). Left for AC#2: per-item Share / Manage access in the OneDrive view and channel Files rows (Teams' context menu: Open, Preview, Share, Copy link, Manage access, Delete, Add to favorites, Add shortcut, Download, Rename, Open in OneDrive, Move to, Copy to, Duplicate), and the Files variant's ··· "Send link in Outlook".
- Not yet seen in Teams: the People-you-choose link body and the organisation / specific-people wording in Access summary.
<!-- SECTION:NOTES:END -->
