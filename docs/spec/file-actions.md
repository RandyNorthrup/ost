# Teams' Files item actions (OneDrive app, channel Files)

The right-click / ··· menu on a file or folder in Teams' OneDrive app, and what each item
does. Teams draws these with OneDrive's own page (`filebrowser.aspx?app=TeamsFile`) in a
frame. OST draws them natively in `desktop/qml/FileActions.qml`, used by `OneDriveView.qml`
and `ChannelFiles.qml`. Measured on winpc 2026-11-11 (Teams 26288) at 1280 x 720 CSS px,
on `ost-share-test.txt` in OST Test 1's My files.

## The menu

The menu is OneDrive's Fabric context menu:

- 216.67 wide, white, radius 4, shadow `0 3.2px 7.2px rgba(0,0,0,.13), 0 0.6px 1.8px rgba(0,0,0,.11)`, no padding.
- Rows are 36 tall with no gap. Each has a 16 px glyph 8 in, the label 14 px #424242 at 32, and a 12 px chevron 8 from the right for a submenu.
- Dividers are 1 px with 4 above and below.
- Submenus are 232 wide, 4 px off the menu, and start 4 below their row.

OST draws these with `MenuPopup`'s `fabric` mode, using Fluent System glyphs in place of OneDrive's MDL2 font.

| A file (.txt) | A folder |
|---|---|
| Open ▸ (Open in Text Editor, Open in app) | — |
| Preview | — |
| Share | Share |
| Copy link | Copy link |
| — | Request files |
| Manage access | Manage access |
| ─ | ─ |
| Delete | Delete |
| Add to favorites | Add to favorites |
| Add shortcut ▸ (Shortcuts, My files, Other locations) | — |
| Download | Download |
| Rename | Rename |
| Open in OneDrive | Open in OneDrive |
| Move to | Move to |
| Copy to | Copy to |
| Duplicate | Duplicate |
| — | Folder color ▸ |
| ─ Version history | — |
| ─ Details | ─ Details |

A video also has "Add to playlist" after Duplicate. Office files' Open ▸ has Open in browser
and Open in app (OneDrive's wording; not yet seen in Teams).

## What each does

- **Open in Text Editor / Open in browser / Open in OneDrive** open the file's web address in
  the browser. Teams opened Edge on winpc.
- **Open in app**: OST saves a copy under `~/.cache/ost/open/<id>/` and hands it to the
  desktop's app (`api::drive::local_copy`).
- **Share** and **Manage access** open OneDrive's share dialog (`docs/spec/onedrive-share.md`):
  the share form, or Manage Access ▸ People.
- **Copy link** makes the file's default link right away, with `ShareLink` and the default
  scope and role from `GetSharingInformation`. On this tenant that is Anyone, edit: kind 5,
  scope 0, `trackLinkUsers: false`. Then "Link created" opens:
  - 480 wide, radius 8, padding 24.
  - A 16 px #107C10 check and "Link created" 20/600 #616161.
  - Close: 32, with a 14 px glyph.
  - The link in a 358.05 x 32 box: white, 0.67 #D1D1D1 border, #424242 underline, radius 4, padding 0 8, 14/20 #616161, cut with "...".
  - A 73.95 x 32 Copy button: 0.67 #7A7A7A border, radius 2, 14/600.
  - 8 below: what the link does ("Anyone with the link can edit", 14/16 #616161) and Settings (14 px gear and text, #5B5FC7) at the right.
  - Copy copies the link. The title becomes "Link copied", the box goes, and the dialog shrinks from 137.33 to 105.33 tall.
  - Settings opens OneDrive's Link settings. With existing access as the default, no link is made: the file's own address is shown, "People with existing access can use the link".
- **Delete** asks first. The dialog is 440 x 240, padding 24, radius 8:
  - "Delete?" 20/28 600 #616161, with a 32 x 31.33 Close (a 20 px dismiss).
  - "Are you sure you want to send this item to the recycle bin?" 14/20, 78 down.
  - Delete and Cancel, both 80 x 32, #5B5FC7, white 14/600, radius 4, 8 apart, 24 from the bottom right.
  - Delete moves the item to the recycle bin.
- **Rename** is the same dialog, 266.67 tall in Teams:
  - The name without its extension in a 32 px box, 89 down: 0.67 #D1D1D1 border, #424242 underline, padding 0 12.
  - The extension after the box (".txt", padded 10 5 0).
  - Update and Cancel.
  - Teams' request is SharePoint's list-item update (`POST …/GetListUsingPath(DecodedUrl=@a1)/items(@a2)` with `{"__metadata":{"type":"SP.Data.DocumentsItem"},"FileLeafRef":"<name>"}`, sent as MERGE). OST renames through Graph (`PATCH /drives/{d}/items/{i}` `{name}`), which does the same.
  - Teams also shows Copilot's "Suggested names" (44 tall) between the box and the buttons. OST leaves that row out, so its dialog is 210 tall.
- **Duplicate** is SharePoint's copy job on the file's site: `POST {site}/_api/site/CreateCopyJobs` with `{"exportObjectUris":[<file>],"destinationUri":<its folder>,"options":{"IgnoreVersionHistory":true,"AllowSchemaMismatch":true,"BypassSharedLock":true,"SameWebCopyMoveOptimization":true,"NameConflictBehavior":2,"CustomizedItemName":{"results":["<stem> Copy.<ext>"]}}}`. Then `GetCopyJobProgress` with the job's `{EncryptionKey, JobId, JobQueueUri}` until `JobState` is 0. Failures are `JobError` / `JobFatalError` events in `Logs`. OST does the same (`api::copy_jobs`).
- **Move to / Copy to** open OneDrive's picker over the window:
  - 1140 x 720 at most, #F5F5F5.
  - Left, 210 wide: "Move to" / "Copy to" 20/44 600 at 24, 14. Then the places as 190 x 36 rows, radius 8, 14 px #424242, the chosen one 600: My files, Shared, Favorites, "Browse by" (People, Meetings), "Quick access" (the libraries you use), More places….
  - Right: the trail ("My files › Attachments", 18/600 #616161), "Search in My Files", New folder and the view switch.
  - The list is on a white card with radius 12 at the top. Columns: Type, Name, Modified, Modified By, Activity (14/600, 48 tall). Rows are 59 tall with a 32 px folder and the name over "n items". Files are greyed and can't be picked.
  - Footer, 80 tall: "Move here" / "Copy here" (93 x 32; disabled where the item already is: white, #EBEBEB border, #D1D1D1 text) and Cancel (80 x 32, #7A7A7A border), 24 from the right.
  - The job is CreateCopyJobs again, to the chosen folder's address. A move sets `IsMoveMode` and keeps version history.
- **Notices** sit under the list, 23 above the view's bottom:
  - 390 wide, #292929, radius 4, padding 12.
  - A 20 px glyph: #92C353 check, #F1707B error, or progress. Text is 13/17 #F0F0F0 at 48. A 24 px dismiss with a #7F85F5 glyph.
  - Wording: "Renamed 1 item", "Copying 1 item" → "Copied 1 item". On failure: "1 item wasn't copied" over SharePoint's message.
  - A move is "Moving 1 item" / "Moved 1 item" / "1 item wasn't moved" (OneDrive's strings; several items: docs/spec/onedrive-rows.md).

## Not yet in OST

- Preview: TASK-0115. Version history is in `docs/spec/version-history.md`, Details in `docs/spec/details-pane.md`.
- Add shortcut ▸, Request files, Folder color ▸, Download of a folder (a zip) and Add to playlist: TASK-0116.
- The picker's Shared, Favorites, Browse by, More places…, Search, New folder and view switch, plus Copilot's Suggested names in Rename: TASK-0117.
- Favorites on folders: Graph's followed items hold files only.
- A team site's file shows "Open in SharePoint" in OST. Teams' wording in channel Files hasn't been captured yet.

## Opening Word, PowerPoint and Excel files

Teams' Settings ▸ Files and links ▸ "Always open Word, PowerPoint, and Excel files in:" decides
how a click on an Office file opens: in the file list, in a chat's file card, or in search.

- On winpc (no Office installed, 2026-11-11), the choices were **Teams** and **Browser**.
  They are stored in the synced `userPersonalSettings.filesSettings.fileOpenPreference` as
  `teamsV2` or `web`.
- With Office installed, Teams adds **Desktop app**, and that choice stays on the device
  ("This setting will only apply to this device."). Teams' own strings announce the move to
  it: "Files now open in Desktop app" and "Word, PowerPoint and Excel files will now open in
  the desktop app for an improved experience". An admin policy (`forceOpenFilesInDesktopApp`)
  can force the desktop app.
- **Teams** opens Office for the web inside Teams' window. OST doesn't embed web pages, so it
  doesn't offer that choice.
- OST offers **Desktop app** when the desktop has an app for Word files: the `xdg-mime`
  default, else the first app in the MIME cache. OST keeps this choice on the device
  (setting `fileOpenIn`) and makes it the default when such an app exists, as Teams does.
  OST then downloads a copy to `~/.cache/ost/open/<id>/` and opens it with that app
  (`Backend::open_file`).
- **Browser** opens the file's web address, and also sets the synced value to `web`.
- Other files always open in the browser.

Not yet in OST: the same page's "Always ask where to save downloaded file" toggle and its
"Links open preference ▸ Always open web links in:" browser picker (TASK-0119).
