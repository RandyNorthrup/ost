# Version history (Teams' Files apps)

What Version history does in Teams' OneDrive app and channel Files. Teams draws
it with OneDrive's page in a frame; OST draws it natively, in the
`versions` popup in `desktop/qml/FileActions.qml`, backed by
`src/api/versions.rs`. Measured on winpc on 2026-11-12, on
`ost-share-test.txt` in OST Test 1's My files.

## Where it is

Version history is in a file's item menu after a divider, and in the selection
bar's ··· menu for one file. Folders don't have it.

## The dialog

- At most 848.4 wide (70% of the frame, 1212 wide), padding 24, radius 8.
- Fluent's 64 shadow (`0 25.6px 57.6px rgba(0,0,0,.22), 0 4.8px 14.4px
  rgba(0,0,0,.18)`), over an `rgba(0,0,0,.4)` backdrop.
- "Version history" in 20/28 600 #616161, with a 32 x 31.33 Close holding a
  20 px dismiss glyph.
- The versions sit on a white card, 316 tall, radius 4, with Fluent's 4
  shadow (`0 1.6px 3.6px rgba(0,0,0,.133), 0 0.3px 0.9px rgba(0,0,0,.11)`).
- Columns: Version 100, then Modified, Size and Modified By at 40%, 20% and
  40% of the rest (279.63, 139.81 and 279.63 at full width).
- The header is 46 tall in 12/20 600 #616161, with a 2 px #F0F0F0 line under
  it. Version's label is at 20, the others at 8.
- Rows are 46 tall. The version label is 16 px #616161 at 20 and opens that
  version. The other cells are 14/20 #5E5E5D at 8. Modified By has a 24 px
  picture at 8 and the name at 48.
- A hovered row is #EBEBEB. Its 28 px "Show more actions for this item" (···)
  sits 63 in and 9 down, and opens a 232-wide menu 4 below it:
  - the current version: **Open File** only;
  - older versions: **Open File**, **Restore** and **Delete Version**.
- Restore and Delete Version act at once, with no question, and the list
  reloads.
- Modified is the version's time in local time ("11/11/2026 10:28 PM"). Size
  uses OneDrive's wording ("56 bytes").

## Requests (SharePoint REST, the file's site)

- **List:**
  `GET {site}/_api/web/GetListItemUsingPath(decodedUrl=@a1)/versions?@a1='{server-relative path}'&$select=VersionId,VersionLabel,Created,CreatedBy/Title,CreatedBy/Email,FileVersion/Url,FileVersion/Length,SMTotalFileStreamSize,IsCurrentVersion&$expand=CreatedBy,FileVersion&$top=5000`.
  The reply is newest first. `Created` is UTC without a zone.
- **Restore:**
  `POST {site}/_api/web/GetFileByServerRelativePath(decodedUrl=@a1)/versions/RestoreByLabel(versionLabel=@a2)`.
  This makes a new current version: restoring 2.0 over 4.0 gave 5.0.
- **Delete Version:** the same path with `RecycleByLabel`, which sends the
  version to the recycle bin.
- **Open File:** the current version opens the file's own address. An older
  one opens `{site}/{FileVersion.Url}`
  (`_vti_history/1024/Documents/ost-share-test.txt`). OST opens both in the
  browser.

## Differences

- When a person has no picture, Teams shows SharePoint's grey silhouette. OST
  shows its usual initials picture.

Harness: `--version-history-test [--version-history-live]`. The live run
restores the oldest version of ost-share-test.txt, then deletes that oldest
version.
