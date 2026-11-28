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
- **Rename** is the same dialog, 240 tall (266.67 with Copilot's Suggested names row):
  - The name without its extension in a 32 px box, 89 down: 0.67 #D1D1D1 border, #424242 underline, padding 0 12.
  - The extension after the box (".txt", padded 10 5 0).
  - Update and Cancel.
  - Teams' request is SharePoint's list-item update (`POST …/GetListUsingPath(DecodedUrl=@a1)/items(@a2)` with `{"__metadata":{"type":"SP.Data.DocumentsItem"},"FileLeafRef":"<name>"}`, sent as MERGE). OST renames through Graph (`PATCH /drives/{d}/items/{i}` `{name}`), which does the same.
  - For some files (a .txt, not an .mp4) Teams adds Copilot's **Suggested names** under the box: a folded 390.67 x 44 row (Copilot glyph, "Suggested names", a chevron) at 133, 25 above the buttons. Expanded, it shows three loading pills ("Loading suggestions"), then three name pills, plus "AI-generated content may be incorrect" (12 px) with Helpful / Not helpful thumbs. On failure: "Something went wrong. Try again".
  - The names come from OneDrive's AugLoop LLM service (`llmScenarioGuid` f44f84d5-dd13-4369-9939-c8cb945fe62f, `augloopFlights` with `enableAnalyzeImagePlugin:true`, the file's `{fileName, siteId, webId, listId, uniqueId}` and a prompt asking for 3 names as NDJSON `{"type":"suggestion","name":…}` lines then `{"type":"done"}`, or `{"type":"error","code":"InsufficientContent|FileNotAvailable|Confidential|UnknownError"}`). Before asking, OneDrive reads the file's `sensitivityLabel` from Graph and skips "Highly Confidential" / "Restricted" protected files.
  - It is offered for OneDrive's document, text and picture types (doc, docx, docm, dot, dotx, dotm, xls, xlsx, xlsm, xlt, xltx, xltm, ppt, pptx, pptm, pot, potx, potm, pdf, txt, rtf, csv, tsv, json, md, odt, ods, odp, jpg, jpeg, png, bmp, tiff, tif) with Copilot. A protected file's row is greyed: "This file is confidential, so its content can’t be accessed".
  - Measured on winpc 2026-11-19 (TASK-0125): the accordion is 390.67 wide (radius 4), 12 under the box. Its 44 tall header has the 16 px Copilot glyph at 10, 14, "Suggested names" (14/20 #424242) at 34, and a 20 px chevron 10 from the right.
  - Open, the names are pills 28 tall (12/16 #242424, 1 px #D1D1D1, radius 14, padding 19, 8 apart), 6 under the header. Loading shows three skeleton pills (150 x 34). Then "AI-generated content may be incorrect" (12/16) with the 24 px Helpful / Not helpful thumbs, 12 from the bottom.
  - With three names, a 28 px "Get new suggestions" button (arrow-sync) sits 32 from the header's right. A pill puts its name in the box and folds the row.
  - Messages (12/16): "This file doesn't have enough content to suggest names.", "This file is no longer available.", or "Something went wrong." with a brand "Try again".
  - The exchange (captured): one AugLoop session per request at `wss://augloop.svc.cloud.microsoft/` (appName "odsp", appPlatform "Web", releaseAudienceGroup "Production", sessionId `alproxy_{guid}`):
    - a SyncMessage with the `AugLoop_OdspCopilot_ODSPCopilotInputSignal` ("main": queryId, the prompt, isNewConversation, `dataSources.dataSources.files` = the file with braced GUIDs, llmScenarioGuid);
    - the "doc" seed, the activation of `AugLoop_OdspCopilot_ODSPCopilotOutputAnnotation`, the token, and the "context" `ODSPCopilotScopeContext` (the file as entity constraint and selection);
    - annotations stream back: Progress messages, then `chatResponse.basinWrite` pieces (each a JSON string) of the NDJSON; status 13 while partial, 0 at the end.
  - OST does the same natively (`api::rename_suggestions`, `examples/rename_suggest`) with its own AugLoop token. The thumbs toggle as Teams' do; OST sends no rating. Harness `--rename-suggest-test`.
- **Duplicate** is SharePoint's copy job on the file's site: `POST {site}/_api/site/CreateCopyJobs` with `{"exportObjectUris":[<file>],"destinationUri":<its folder>,"options":{"IgnoreVersionHistory":true,"AllowSchemaMismatch":true,"BypassSharedLock":true,"SameWebCopyMoveOptimization":true,"NameConflictBehavior":2,"CustomizedItemName":{"results":["<stem> Copy.<ext>"]}}}`. Then `GetCopyJobProgress` with the job's `{EncryptionKey, JobId, JobQueueUri}` until `JobState` is 0. Failures are `JobError` / `JobFatalError` events in `Logs`. OST does the same (`api::copy_jobs`).
- **Move to / Copy to** open OneDrive's picker over the window:
  - 1140 x 720 at most, #F5F5F5.
  - Left, 210 wide: "Move to" / "Copy to" 20/44 600 at 24, 14. Then the places as 190 x 36 rows, radius 8, 14 px #424242, the chosen one 600: My files, Shared, Favorites, "Browse by" (People, Meetings), "Quick access" (the libraries you use), More places….
  - Right: the trail ("My files › Attachments", 18/600 #616161), "Search in My Files", New folder and the view switch.
  - The list is on a white card with radius 12 at the top. Columns: Type, Name, Modified, Modified By, Activity (14/600, 48 tall). Rows are 59 tall with a 32 px folder and the name over "n items". Files are greyed and can't be picked.
  - Footer, 80 tall: "Move here" / "Copy here" (93 x 32; disabled where the item already is: white, #EBEBEB border, #D1D1D1 text) and Cancel (80 x 32, #7A7A7A border), 24 from the right.
  - The job is CreateCopyJobs again, to the chosen folder's address. A move sets `IsMoveMode` and keeps version history.

### The picker's places, search and New folder

Measured on winpc on 2026-11-12, as OST Test 1.

- **Shared** opens "Shared with you": the folders shared with you (the trail
  reads "Shared with you"). OST Test 1's is empty.
- **Favorites** with nothing favourited shows a star illustration and "Items
  you favorite will show up here".
- **Browse by People** lists the people who shared folders with you, and
  **Meetings** the folders from your meetings. In Teams both show Teams' own
  "Please sign in" prompt instead, a bug in Teams 26288. OST lists the
  folders from OneDrive's shared views (the recent files service and shared
  folders, grouped by who shared them, `src/api/shared_files.rs`) and the
  meetings' recording folders.
- **More places…** opens "Shared libraries": "Recent" and "Your Teams"
  sections of site cards (a 40 px initials tile, the name, and a second line
  such as "Site Assets"). A card opens that library.
- Only folders are listed in these places; files can't be picked.
- **Search** is a 240 x 32 round box at the top right: "Search in {folder}",
  or "Search in all files" in a place. Enter shows "Search results" with a
  back arrow (measured on winpc 2026-11-13, coordinates in the picker's
  frame with the folder pane at 82):
  - the tabs "All files" and "My files" (16/22 semibold #242424, 4 px
    padding, at 98 and 170.8, y 85; the chosen one underlined 2 px in the
    brand colour), then 22 further the date filter: a 32 tall pill (118.1
    wide for "All dates": the choice 14/600 at 18.6, a 16 px chevron 10
    after it) whose menu (4.6 right and 4.7 under it, 170.7 wide, no
    padding, rows 32 tall 2 apart, a check at 8 and the label 14/20 #424242
    at 30) offers All dates, Today, Last 7 days, Last 30 days, Last 3 months
    and In the last year; then a "Person" pill (102.3 wide; "Filter by
    people") — see below;
  - the white card at 136.7 with the columns Name (the rest), Modified
    (200), Modified by (215.9) and Location (198.9): the header 48 tall,
    14/600, Name's label 20.6 in and the others 8.6; rows 56 tall: a 32 px
    folder 20 in, the name (14 px #242424) at 68 and 9.8 down over
    "Created by: {name}" (12 px #616161) at 29.5; Modified ("Sun at 3:41
    PM", OneDrive's client wording), Modified by (8 in) and Location (12 in)
    in 14 px #616161.
  - Only folders are found: the query and template Teams sends are
    `{q} (path:"{personal}/Documents" OR ParentLink:"{personal}/Documents*"
    OR DocumentLink:"{personal}/Documents*")` for My files (no path limit
    for All files) and `({searchterms}) (ContentTypeId:0x010100* OR
    ContentTypeId:0x010102* OR ContentTypeId:0x0120*) AND
    ((ContentTypeId:0x010100* OR ContentTypeId:0x0120*) AND
    (ContentTypeId:0x0120* NOT HtmlFileType:"OneNote.Notebook" NOT
    ParentLink:SiteAssets))`, 25 rows by relevance.
  - The date filter appends ` AND (LastModifiedTime>={ISO} )` with midnight
    UTC 0, 7, 30, 90 or 365 days back; the Person filter appends ` AND
    (ModifiedBy:"{name}" OR author:"{name}" …)` per person chosen.
  - Location (OneDrive's search code): the item's path under its web,
    first "My files" for your own OneDrive, "{site title}'s OneDrive" for
    someone else's ("Shared" when untitled), else the site's title (else the
    web address's last two parts joined by "-"); then its folders, with the
    library left out when it is Documents or Shared Documents. Two parts
    show as "A › B"; more as "A › … › Z" ("A › B › … › Z" in your own
    OneDrive); the last part ellipsizes, the tooltip is the parts joined by
    "/", and a tap opens the folder it is in. Other sites' first part has the
    site's picture and someone else's OneDrive their picture.
  - Teams asks SharePoint:
    `POST {personal}/_api/sp.searchresultitemcollection.getsearchresultsasstream?textDecorations=1&scenario='onedriveweb'`
    with `{"payload": …}`: one `EntityRequests` entry for `File` from
    `OneDriveBusiness`; All files goes through substrate.office.com search,
    whose sign-in failed in Teams on 2026-11-13 ("Please sign in" that
    wouldn't close), so its rows and the Person filter's popup weren't
    measured.
  - OST sends the same query and template through Graph's `POST
    /search/query` (`driveItem`, 25 rows, with the managed properties
    IsContainer, SiteTitle, SPWebUrl, SiteTemplateId and ParentLink); a
    folder opens in the picker.
  - The Person filter, from OneDrive's code (odsp-web-prod_2026-11-06.005).
    Teams' own picker still stops at its "Please sign in" on winpc: the
    substrate token is fetched in a popup that WebView2 blocks.
    - A pill 32 tall (radius 16, padding 5 14, 14/600, a 1 px stroke, a
      chevron) reading "Person", or the person's 20 px picture and name on
      the brand tint once picked. One person at most.
    - Its menu (320 wide, radius 8): a round 32 px "Search for a person"
      box; people rows (a check slot, the 20 px picture, the name; 104 tall
      before typing, 168 after); "Loading people…" / "No people found"; Clear
      (12/600).
    - Picking appends ` AND (ModifiedBy:"{name}" OR author:"{name}")` to the
      query. OST finds the people with Graph's `/me/people` (organization
      users and guests).
  - Location's picture, 16 px before the name: another site's logo
    (OneDrive's `siteiconmanager/getsitelogo?siteUrl='…'` on your OneDrive),
    or the picture of the person whose OneDrive it is (that drive's owner).
    Harness `--picker-person-test`.
  - On 2026-11-12 search failed tenant-wide: Teams stayed on its loading
    placeholders, and SharePoint search, Graph search and Graph's
    `sharedWithMe` (since retired) all
    answered 500 to 504. OST shows "Sorry, something went wrong." in the list
    and logs the service's answer; Teams' own failure wording is still to be
    captured.
- **New folder** (in a folder, not in places or search results): an inline
  name row, "New folder" selected. Enter creates it and the picker opens it
  ("This folder is empty"). Teams sends
  `POST {site}/_api/web/folders/AddUsingPath(DecodedUrl='…/name',overwrite=false)`;
  OST creates it with Graph (`POST …/children` with `folder: {}`); a name
  already in use gets a number.
- OST numbers its picker requests and drops an answer to an older one, so a
  slow place can't replace the one you opened after it.

### The picker's views and Quick access

Measured on winpc on 2026-11-12.

- **The view switch** (48 x 40 at the header's right, after New folder): the
  view's glyph and a chevron, tooltip "View options". Its menu is 172 wide
  with 36-tall rows: List, Compact List and Tiles, the current one ticked.
  The choice lasts while the picker is open.
  - **List**: Type 55, Name 270, Modified 170, Modified By 150, Activity.
    Rows are 59 tall: a 32 px type icon, the name over "n items" or the
    size ("82.7 KB •" and a people glyph when shared). Activity is a 14 px
    #0078D4 glyph, then the text and its time (14 px #424242), from
    SharePoint's row data as in the files list.
  - **Compact List**: Type 55, Name 300, Modified 150, Modified By 150,
    File Size 150, Sharing 170, Activity. Rows are 32 tall with a 20 px icon
    at 22, 6.
  - **Tiles**: no white card. Folders are the files list's folder tiles
    (176 x 171, the drawing with its count, the name and date). Videos are
    304 x 171 pictures with the name (14 px) and date (12 px) in white on a
    76-tall nameplate (`linear-gradient(to top, rgba(0,0,0,.65), .553 at 55%,
    .196 at 80%, 0)`). Other files are their 74 x 96 picture. Tiles are 8
    apart, from the card's top left + 8.
  - Files can't be picked: rows at 45% and tiles at 50% opacity.
  - Dates use the files list's wording ("Sunday at 3:41 PM").
- **Quick access** (the picker and the OneDrive pane): the libraries you
  pinned, then the ones you used lately.
  - Teams reads `POST {your OneDrive}/_api/SP.PinnedItems.GetItemsBy` for
    the pins and `GET {your OneDrive}/_api/sp.QuickAccessItemCollection.GetQuickAccessItems`
    for the recent ones (`RecentDocumentLibraries`, a JSON string; its
    `PinnedDocumentLibraries` stays empty).
  - A row (36 tall) shows a 20 px tile (radius 4, the site's acronym on its
    `siteColor`), then the site's name, plus " - {library}" for a library
    other than the site's default one ("OST Test Team - Site Assets").
  - "Quick access" has a 16 px (i) with the tooltip "Frequently used team
    locations, including shared libraries and Teams channels."
  - Hovering a row shows a 24 px pin button at its right (16 px glyph,
    #616161); a pinned library keeps a solid pin. Tooltips: "Pin {name} to
    Quick access" / "Unpin {name} from Quick access".
  - Pinning sends `POST …/_api/SP.PinnedItems.AddItem` with `{"pinnedItem":
    {webId, listId, title, listUrl, siteUrl, siteTitle, siteIconUrl, siteId,
    isDefaultDocumentLibrary, siteColor, siteAcronym}}` (the icon is your
    OneDrive's `siteiconmanager/getsitelogo?siteUrl='…'`); unpinning sends
    `SP.PinnedItems.RemoveItem` with `{listId, siteId, webId}`. Both answer
    200.
  - The notices: "Updating {library}", then "Pinned {library} to Quick
    access" or "Unpinned {library} from Quick access"; on failure "{library}
    wasn't pinned" / "wasn't unpinned" (OneDrive's strings).
  - More places…' "Recent" lists the same libraries; "Your Teams" lists
    your teams' libraries.
- **Navigation Pane**: the title row (16, 18; 190 x 36) is a button whose
  20 px glyph shows on hover at its right. It folds the places into a
  68-wide rail of 36 x 36 icons (from 16): the expand glyph, My files,
  Shared, Favorites, the Browse by chevron, People, Meetings, a 36-wide line
  where "Quick access" was, the library tiles and "…" for More places. The
  list then starts at 98.67 instead of 240.67.
- **Browse by** (36 tall) folds People and Meetings away; its 16 px chevron
  shows on hover (down while open, up while folded), and always on the rail.
- **Notices** sit under the list, 23 above the view's bottom:
  - 390 wide, #292929, radius 4, padding 12.
  - A 20 px glyph: #92C353 check, #F1707B error, or progress. Text is 13/17 #F0F0F0 at 48. A 24 px dismiss with a #7F85F5 glyph.
  - Wording: "Renamed 1 item", "Copying 1 item" → "Copied 1 item". On failure: "1 item wasn't copied" over SharePoint's message.
  - A move is "Moving 1 item" / "Moved 1 item" / "1 item wasn't moved" (OneDrive's strings; several items: docs/spec/onedrive-rows.md).

## Folder color and Request files (a folder's)

### Folder color ▸

The menu row shows the current colour as a 12 px dot before its chevron.
Hovering it opens a 164 x 160 card beside the menu (to its left near the
window's right edge):

- 16 colours as 24 px circles, 40 apart, four to a row: Yellow, Grey, Dark
  red, Light red, Dark orange, Light orange, Dark green, Light green, Dark
  teal, Light teal, Dark blue, Light blue, Dark purple, Light purple, Dark
  pink, Light pink.
- The current colour has a blue ring.

Picking one sends
`POST {site}/_api/foldercoloring/stampcolor(DecodedUrl=@a1)` with
`{"coloringInformation":{"__metadata":{"type":"SP.FolderColoringInformation"},"ColorHex":"{code}"}}`.

The code is OneDrive's index, not the picker's order:

| Code | Colour |
|---|---|
| 0 | Yellow |
| 1 | Dark red |
| 2 | Dark orange |
| 3 | Dark green |
| 4 | Dark teal |
| 5 | Dark blue |
| 6 | Dark purple |
| 7 | Dark pink |
| 8 | Grey |
| 9 | Light red |
| 10 | Light orange |
| 11 | Light green |
| 12 | Light teal |
| 13 | Light blue |
| 14 | Light purple |
| 15 | Light pink |

- The list reads the colour from the `_ColorHex` field.
- OneDrive draws a coloured folder with six shades per colour: main,
  background, accent, gradient start, gradient stop and the count colour.
  For Light blue they are #86C8F7, #73B3EB, #1F64A1, #9FDAFF, #6EB6F0 and
  #004881.
- OST recolours its folder drawing with those shades (`FluentIcon.swaps`).

### Request files

Request files comes after Copy link. It is a two-step dialog, 600 wide with
padding 24 and radius 8.

**Step 1, "Request files for this folder"** (24/28 500):

- A folder glyph and "Let the recipients know which files you're
  requesting."
- A 32 px box, "Enter a description". If it's empty, "Please type a name for
  the request." shows in 12 px #BC2F32 with an error glyph.
- "Recipients will only see the file description you've entered and can
  only upload files to this folder." (12/20).
- **Next** and **Cancel**.
- Next makes the link:
  `ShareLink {createLink:true, settings:{allowAnonymousAccess:true, linkKind:6, role:8, description, …}}`.
  A folder has one such link, so a second request returns the same link.

**Step 2, "Send file request"**:

- "Here's the link people can use to upload files" (15/20 600).
- The link in a 418 x 34 box, with Copy link (12/600, "Copied" after).
- "Anyone with the link can upload files".
- "Or you can send it via email": a To picker (people search) and a Message
  box.
- The button is **Done**, or **Send** once someone is picked. Send makes the
  same `ShareLink` call with `emailData:{body}` and `peoplePickerInput`.

**Then a confirmation**: a 44 px #107C10 check, "Your file request was
created!" (or "…sent!"), and "We will notify you when someone uploads files."

Errors read "Something went wrong, please try again" and "Send file request
email failed.".

Harness: `--folder-extras-test [--folder-extras-live]`. The live run colours
Attachments Light blue and back to Yellow, and makes a request, then removes
its link.

## Add shortcut ▸ (a file's)

Add shortcut comes after Add to favorites, and its submenu lists Shortcuts, My
files and Other locations. OneDrive's code (its "Stasher") posts:

`POST {host}/_api/v2.1/drives/{drive}/items/{target}/children`

with this body:

`{"name":"<file name without extension>","remoteItem":{"sharepointIds":{listId,listItemUniqueId,siteId,siteUrl,webId}},"file":{},"@microsoft.graph.conflictBehavior":"rename"}`

The target depends on the choice:

- **Shortcuts**: `drives/me/special/shortcuts`, on your OneDrive's host.
  OneDrive makes this special folder the first time. From then on Teams
  lists it in My files (with its own icon: docs/spec/onedrive-rows.md), and
  so does OST.
- **My files**: `drives/me/items/root`.
- **Other locations**: OneDrive's "Pick a folder" picker with **Select** and
  **Cancel**. The target is the chosen folder (`items/{uniqueId}`), or the
  library's `items/root`.

The shortcut shows up as "{name}.url".

The notice reads "Added {name} as a shortcut to {place}.", where {place} is
Shortcuts, My files or the folder's name. In Teams the place is a link. On
failure: "Something went wrong so we couldn't add {name} as a shortcut to
{place}. {error}".

OST uses its Move/Copy picker in "Pick a folder" mode for Other locations,
with the same places as Teams' picker.

## Add shortcut to OneDrive ▾ (a channel's folder, TASK-0331)

A channel's Shared tab has **Add shortcut to OneDrive ▾** in its bar. It is
a menu button with **Shortcuts** and **My files**. Teams' OneDrive frame
posts the same Stasher body for the channel's folder (captured on winpc on
2026-11-26):

`POST {personal}/_api/v2.1/drives/me/items/root/children` (or
`drives/me/special/shortcuts/children`)

with this body:

`{"name":"OST test channel","remoteItem":{"sharepointIds":{listId,listItemUniqueId,siteId,siteUrl,webId}},"@microsoft.graph.conflictBehavior":"rename"}`

A folder's body has no `"file": {}`. SharePoint names the shortcut "{team}
- {channel}". The notice reads "Added 1 shortcut to My files in OneDrive"
(or to Shortcuts). A failure reads "1 shortcut wasn't added" with
SharePoint's reason, such as "You already have a shortcut to this folder".

OST used Graph's `POST /me/drive/root/children` with a `remoteItem` id.
That made the shortcut, but OST's My files never showed it: Graph's
children (and SharePoint's list rows with OST's own RenderOptions) leave
shortcuts out. Teams' list asks `RenderListDataAsStream` with RenderOptions
5691143, which returns them as rows with ProgId `AddToOneDrive.MountPoint`
and a `RemoteItem` (the target's drive and item ids, site, list and title).
OST now posts OneDrive's body from `api::copy_jobs::add_shortcut` and lists
the shortcuts from those rows (`api::list_rows::shortcuts`): the row is the
shortcut itself (its own Graph and SharePoint ids, so Delete, Rename, Move
to and Copy to act on the shortcut), opening goes to the target,
and Sharing reads "Owner: {team}". Harness: `--channel-files-test
--channel-files-shortcut`, then `--channel-files-unshortcut`.

## Favorites (files and folders; TASK-0359, OneDrive bundle 2026-11-13)

- **Who offers it:** OneDrive's `canFavoriteItem` (FavoriteAction, module
  7142): any item of a document library that isn't a favorite yet, except
  a shortcut (mount point) or a `.url` link; folders too. `canUnfavoriteItem`
  offers Remove from favorites for a favorite. The ··· and right-click
  menus, the selection bar's ··· and the row's hover star (the name cell's
  hero commands use the same two checks) follow them. The selection bar's
  Add to favorites takes 1 to 20 items, each a favorite or one it can add.
- **The call** (OneDrive's `favoriteItems` / `unfavoriteItems`, data source
  4177): `POST {your OneDrive's host}/_api/v2.1/favorites/followedListItems/
  oneDrive.add` (or `.remove`), header `Caller: ODBWeb`, body
  `{"value": [{siteId, webId, listId, listItemUniqueId}]}`, or
  `{siteUrl, url}` when the four ids aren't all real GUIDs. OST takes the
  ids from Graph's `sharepointIds` (`api::drive::set_favorite`, the same
  call for files and folders; it used Graph's legacy `follow` before).
- **Where they show:** Teams' Favorites view lists OneDrive's
  `sp.FavoriteItemCollection.GetFavoriteItems?top=500` on your OneDrive's
  site; OST's Favorites view reads the same list.

## Not yet in OST

- Preview, Version history and Details are in `docs/spec/file-preview.md`, `docs/spec/version-history.md` and `docs/spec/details-pane.md`.
- A team site's file shows "Open in SharePoint" in OST. Teams' wording in channel Files hasn't been captured yet.

## Add to playlist (a video's)

Measured on winpc 2026-11-19 (TASK-0123) with "OST TEST 123 clip.mp4" and a
playlist made with Teams' own New playlist.

- The menu item comes after Duplicate (also in the selection bar's ···). It
  opens OneDrive's picker in its playlist mode (`FilePicker.aspx`, scenario
  `StreamPlaylist.AddToPlaylist`) in the Move picker's frame:
  - left: "Add to playlist" (20/600 #242424 at 24, 20); My lists, Recent
    lists and Favorites (204 x 40 from 12, 74.67, a 16 px glyph at 24);
    "Quick access" (14/600) with your sites (a 24 px tile, the name at 56);
    "More places...";
  - right: the place's name (18/600), Search, and the list on a white card:
    Type, Name and Modified (Recent lists: Accessed). Rows are 59 tall with
    the 32 px playlist icon. Empty: "This folder is empty"; Favorites:
    "Items you favorite will show up here";
  - the tray, 24 from the bottom right: New playlist, Done (primary,
    disabled until a playlist is picked) and Cancel.
  - Teams' picker is 720 tall in a 632 frame at 1280 x 680, so its tray is
    cut off there (a Teams bug). OST keeps it inside the window.
- Lists:
  - My lists: `GET {my host}/_api/SP.PersonalListsProxy.GetPersonalListsProxy?templateTypeId='3a867b4a-7429-0e1a-b02e-bf4b240ff1ce'`;
  - Recent lists: `sp.RecentListProxy.GetRecentListsProxy` with the same template;
  - Favorites: `sp.FavoriteItemCollection.GetFavoriteItems?top=500`.
- New playlist opens Microsoft Lists' form: Name * ("Playlist"), Description
  ("What is your list about?"), Save to * (My lists), Create (#892FFF) and
  Cancel.
  - Create sends `SiteScriptUtility.ApplyListDesign()` with
    `{listDesignId: 3a867b4a-…, store: 1, runtimeParameters: {Playlist_listName, Playlist_description, Playlist_color: 0, Playlist_addNavLink: false, Playlist_icon: 12}}`.
  - The list is `{personal}/Lists/{name}`, and the video is added to it.
- Adding sends `POST {personal}/_api/web/GetList(@a1)/AddValidateUpdateItemUsingPath()` with:
  - Thumbnail: `{host}/_api/v2.0/drives/{d}/items/{i}/thumbnails/0/c90x150/content?prefer=noredirect,closestavailablesize&cb={eTag}`;
  - Title (the name without its extension), Owner (the person JSON), Duration ("00:00:06");
  - VideoIdentifiers (`{UniqueId, Id, WebAbsoluteUrl, ListFullUrl, WebDavUrl}`) and ContentType Item.
  - Owner is left out if the list refuses it.
- Notices: "Adding to the playlist", then "Added to the playlist" with View
  (the list's `AllItems.aspx?env=WebViewList`). On failure: "Couldn't add to
  the playlist." over "Sorry, there was a problem adding to this playlist,
  please try again." (refused: "Sorry, you do not have permission to add to
  this playlist. Select a different one.").
- OST: `api::playlists`, PlaylistPicker.qml; harness `--playlist-test`.

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
- **Teams** opens Office for the web inside Teams' window: the Word, Excel or PowerPoint app's
  page in Teams' app host, full screen beside the app bar, the file named in its context
  (measured 2026-11-16, app-host.md "Office files in Teams"). OST offers it first, as Teams
  does, and makes it the default when this device has no choice yet; it opens the file the same
  way (`api::office_open`, the "office" slot in the app bar) and sets the synced value to
  `teamsV2`.
- OST offers **Desktop app** when the desktop has an app for Word files: the `xdg-mime`
  default, else the first app in the MIME cache. OST keeps this choice on the device
  (setting `fileOpenIn`) and makes it the default when such an app exists, as Teams does.
  OST then downloads a copy to `~/.cache/ost/open/<id>/` and opens it with that app
  (`Backend::open_file`).
- **Browser** opens the file's web address, and also sets the synced value to `web`.
- Other files always open in the browser.

### Downloads and links (the same page)

**Downloads ▸ "Always ask where to save downloaded file"**:

- It is a toggle on this device. Teams' desktop shell keeps it
  (`SetDownloadLocationPromptState`).
- When it's on, each download first asks where to save, suggesting the file's
  name in the download folder.
- In OST this covers chat files, OneDrive files and zips:
  - the backend raises `save_as_requested`;
  - Main.qml shows a save dialog;
  - `save_as_answer` continues the download to the chosen path, or cancels it.

**"Links open preference ▸ Always open web links in:"**:

- A 293 x 30 dropdown. On winpc it offered only **Default browser** and
  **Microsoft Edge**, with Edge chosen, even though Chrome was installed.
- OST offers Default browser, plus Microsoft Edge when a `microsoft-edge`
  command is installed. It defaults to Edge when Edge is there, as Teams does.
- OST makes its handler (`Backend::open_web_link`) Qt's URL handler for
  http and https. Every web link OST opens then goes to the chosen browser:
  Edge, or `xdg-open`. Office files opened in the browser follow the same
  choice.

Harness: `--files-links-test`, run with a stand-in `microsoft-edge` on PATH
that records its URL. It checked that a link goes to Edge and that a download
lands at the path the dialog gave.
