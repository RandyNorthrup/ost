---
id: TASK-0331
title: Add shortcut to OneDrive reports success but adds nothing
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T17:03:00Z'
labels:
  - bug
  - files
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). Add shortcut to OneDrive reports success, but no shortcut appears in OneDrive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add shortcut to OneDrive creates the shortcut (visible in OST, Teams and OneDrive on the web), and reports an error when it fails
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' channel Shared tab "Add shortcut to OneDrive" on winpc (CDP network of the filebrowser frame).
2. Post OneDrive's Stasher body for the folder (no "file") to drives/me/items/root or special/shortcuts, from the channel toolbar's menu (Shortcuts, My files).
3. Report OneDrive's notices: "Added 1 shortcut to … in OneDrive" / "1 shortcut wasn't added" with SharePoint's reason.
4. Unit test from the capture; live check on linuxlt, visible in OST, Teams and OneDrive web; remove test shortcuts.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc capture 2026-11-26: Teams' channel Shared tab "Add shortcut to OneDrive ▾" is a menu (Shortcuts, My files). It posts OneDrive's Stasher body for the folder (no "file") to {personal}/_api/v2.1/drives/me/items/root/children; SharePoint names it "{team} - {channel}"; notice "Added 1 shortcut to My files in OneDrive".
- Cause: OST's Graph POST did make "OST Test Team - General" (2026-11-25 14:06), but OST never showed it: Graph's children and OST's RenderListDataAsStream rows leave shortcuts out. Teams' list asks RenderOptions 5691143, which returns them (ProgId AddToOneDrive.MountPoint, RemoteItem).
- Fix: channel toolbar menu posts OneDrive's body (copy_jobs::add_shortcut, folder flag); errors worded as OneDrive ("1 shortcut wasn't added. You already have a shortcut to this folder"); My files lists shortcuts from list_rows::shortcuts (own ids for Delete/Rename, target ids to open, Sharing "Owner: {team}").
- Live on linuxlt (ost-test1): --channel-files-shortcut → "Added 1 shortcut to My files in OneDrive", listed in OST's My files and in Teams' OneDrive My files (OneDrive's web list) on winpc; repeat → "1 shortcut wasn't added. You already have a shortcut to this folder". --channel-files-unshortcut removed the test shortcuts (also the one made in Teams during the capture); the General channel folder is intact.
<!-- SECTION:NOTES:END -->
