# Teams' OneDrive app rows and selection bar

How a folder's files list looks and acts in Teams' OneDrive app (My files, a
folder, a library). Teams draws it with OneDrive's own page
(`filebrowser.aspx?app=TeamsFile`) in a frame. OST draws it natively in
`desktop/qml/OneDriveView.qml`, with SharePoint's row data from
`src/api/list_rows.rs`.

Measured on winpc on 2026-11-12 (Teams 26288, OneDrive build
odsp-web-prod_2026-10-30.004), at 1280 x 720 CSS px, in OST Test 1's My files.

## Where the columns come from

Teams' list loads the folder with SharePoint's
`POST {site}/_api/web/GetListUsingPath(DecodedUrl=@a1)/RenderListDataAsStream`
(`RenderOptions` 5691143). Graph has no equivalent for these per-row fields:

- **`Modified.FriendlyDisplay`**: SharePoint words the date itself, as
  `relative|future|kind|a|b`. The kinds are:
  - 1: "A few seconds ago"
  - 2: "About a minute ago"
  - 3: "{n} minute(s) ago"
  - 4: "About an hour ago"
  - 5: "Yesterday at {time}"
  - 6: "{n} hour(s) ago"
  - 7: "{weekday} at {time}"
  - 8: "{n} day(s) ago"
  - 9: "Today"

  A code starting with `0|` is shown as is ("0|November 5").
- **`Modified`**: the full date, used as the tooltip ("11/11/2026 10:28 PM").
  SharePoint gives it in the site's regional time zone.
- **`PrincipalCount`**: the number of people with access. Sharing reads
  "Shared", with a 14 px people glyph, when it is above 0. Otherwise it reads
  "Private".
- **`Created_x0020_Date.ifnew`**: "1" for an item created lately. Its name then
  gets OneDrive's "New" mark: a 7.92 x 12 glimmer before the name.
- **`_activity`**: the file's latest activity, as
  `{FileActivityType, FileActivityTimeStamp, FileActivityUsersOnPage[{DisplayName, Id}]}`.

SharePoint fills in `FriendlyDisplay` only for a browser's User-Agent, so OST
sends Teams web's User-Agent (`api::client::TEAMS_WEB_UA`). OST asks for the
same five fields with a `ViewXml` and the folder's `FolderServerRelativeUrl`.
It then joins the rows to Graph's items by `sharepointIds.listItemUniqueId`.

Views without SharePoint rows (Shared, Favorites and so on) word Graph's
times with the same rules, applied locally (`list_rows::friendly_at`):

- Under a minute: "A few seconds ago".
- Under 2 minutes: "About a minute ago".
- Under an hour: minutes.
- Under 2 hours: "About an hour ago".
- Earlier the same day: hours.
- The day before: "Yesterday at {time}".
- Earlier since Sunday: the weekday and time.
- Within 7 days: "{n} days ago".
- Older: "November 5", plus the year if it isn't this year.

The 2026-11-12 rows confirm these cut-offs: Sunday is "Sunday at 3:41 PM",
Friday the 6th is "6 days ago", and the 5th is "November 5".

### Activity

The activity type sets what the column says and its glyph:

| Type | Kind | Glyph |
|---|---|---|
| 4, 5, 16 | edit | Edit |
| 6, 7 | comment | Comment |
| 8, 13, 15 | comment reply | Reply |
| 9 | share | Share |
| 11, 12 | mention | Accounts |
| 28, 29, 31 | create task | Groupedlist |
| 30 | complete task | Groupedlist |

For a mention, share or task, the first user listed is the one who did it and
the rest are the people it was for. You come first and are called "You".
Wordings, from OneDrive's strings:

- **Edit:** "You edited", "{name} edited".
- **Comment:** "{name} commented", "{name} + {n} other(s) commented".
- **Comment reply:** "{name} replied to a comment".
- **Share, with no recipients:** "You shared this file", "{name} shared this file".
- **Share, with recipients:** "{name} shared with you", "You shared with {name}", "{name} shared with {name} + 1 other".
- **Mention:** "{name} mentioned you", "You mentioned {name}".
- **Task:** "{name} created a task for {name}", "You completed the task".

The column shows a 16 px glyph at 12. Next to it is the text (12 px #616161)
followed by the activity's time in OneDrive's client wording. That time reads:

- Under 2 minutes: "Just now".
- Under an hour: "{n}m ago".
- Earlier the same day: "{n}h ago".
- The day before: "Yesterday at {time}".
- Within 6 days: "Sun at 3:41 PM".
- Older: "Nov 5", plus the year if it isn't this year.

The line is cut with "…".

Examples seen: "You shared this file Yesterday at 10:37 PM", and, on meeting
recordings, "SharePoint App shared with Randy Northrup + 1 other Sun at
3:41 PM".

### File size

OneDrive's wording: "1 byte" and "{n} bytes", then KB, MB, GB and TB, by 1024.
Below 10 it shows two decimals, below 100 one, and above that none. Examples:
"26.0 KB", "7.66 MB", "37.5 MB". A folder shows "{n} items" or "1 item".

## The table

- The card is white, radius 4, with a 0.67 #F0F0F0 border.
- Columns: selection 56, Type 40, Name 216 (it takes the spare width),
  Modified 136, Modified By 136, File size 91, Sharing 81, Activity 119.
- The header is 49 tall with a 0.67 #F0F0F0 line under it. Labels are
  14/600 #616161 at 10.67. Type shows a 16 px document glyph.
- Rows are 49 tall. Text is 14 px #616161, padded 14 8 11 12.
- The Type column has a 32 px file-type icon at 6, 8. Folders use OneDrive's
  yellow folder. OneDrive's Shortcuts folder (Add shortcut's; ProgId
  `AddToOneDrive.SpecialFolder`, Graph `specialFolder` "shortcuts") is
  listed like any folder, with Fabric's blue `companyfolder` icon; the
  Move/Copy picker shows it as a plain folder.
- Hover gives the row an #EBEBEB background, inset 8 on both sides, radius 8,
  48 tall (a 1 px white gap above).
- A selected row is #E9EAF6 with its name in 600.
- The selection circle (18 px at 29, 14, white with a 0.67 #424242 ring) shows
  on hover. Selected, it is #5B5FC7 with a white check. The header's
  "Select all rows" circle works the same way for every row.
- On hover, or while the row is selected, three 28 px buttons follow the name,
  8 after it: More Actions (···), Share and "Add this item to Favorites" (the
  star). Their glyphs are 16 px #605E5C.
- A click on the name opens the item. A click elsewhere selects only that row;
  Ctrl+click adds it to the selection or takes it out. A double click opens.
- Right-click and ··· open the item menu (`docs/spec/file-actions.md`).

## The selection bar

With rows selected, the title line becomes OneDrive's command bar:

- A white card 52 tall, from 16 down, radius 12, with a
  `0 3.2px 7.2px rgba(0,0,0,.133), 0 0.6px 1.8px rgba(0,0,0,.11)` shadow and
  padding 0 6 0 10.
- Buttons are 32 tall, 4 apart. Each has a 16 px glyph at 8, the label
  (14 px #616161) at 32, an optional 12 px chevron after it, and 8 at the end.
- The commands depend on what is selected:

| Selected | Commands | ··· |
|---|---|---|
| One file | Open ▾ (Open in Text Editor or Open in browser, Open in app), Share, Copy link, Delete, ··· | Add to favorites, Add shortcut ▸, Download, Duplicate, Move to, Copy to, Rename, Open in OneDrive, Version history |
| One folder | Share, Copy link, Request files, Delete, ··· | Add to favorites, Download, Duplicate, Move to, Copy to, Rename, Open in OneDrive |
| Several | Delete, Add to favorites, Download, ··· | Duplicate, Move to, Copy to |

- Open's icon is the file's app icon for Office files (Word for .docx) and
  OneDrive's OpenFile glyph otherwise.
- The menus are 232 wide. Open's starts at its button +4. The ··· menu's right
  edge is 4 inside its button's. Both hang from the bar's bottom.
- At the right: Sort ▾, then "✕ {n} selected", then a divider, the view switch
  and Details. "✕ {n} selected" is 0.67 #D1D1D1, radius 20, with a 12 px
  dismiss at 12.67 and the text at 36.67; it clears the selection.
- Delete of several asks "Are you sure you want to send these items to the
  recycle bin?".
- Several items go into one copy job: CreateCopyJobs with every source and, for
  Duplicate, a name for each.
- The notices use OneDrive's counted strings:
  - while working: "Copying {n} items", "Moving {n} items";
  - when done: "Copied {n} items", "Moved {n} items";
  - on failure: "{n} items weren't copied", "{n} items weren't moved".

## A subfolder's own bar

In a subfolder (not at the top of My files or a library), with nothing
selected, the top line is the folder's command bar, without the white card:

- At 16 down, 52 tall, padding 0 6 0 10, the same 32-tall buttons: **Share**,
  **Copy link**, **Download** and **Open in OneDrive** (OneDrive's Share,
  Link, download and OneDriveLogo glyphs). They act on the folder itself:
  the share dialog, the link dialog, a zip named after the folder, and the
  folder in the browser.
- Sort ▾, the view switch and Details stay at the right.
- The trail moves under the bar, 68 lower (the crumbs' tops at 96): the
  folders above are 18/400 #616161, the one you're in 18/600, with a 12 px
  #424242 chevron 4 either side.
- The list starts at 144.67 instead of 76.67.

With rows selected the white selection bar takes the top line and the trail
stays where it is. At the top of My files the title line holds "My files" with
Sort, the view switch and Details, and the list starts at 76.67.

OST loads the folder's own item with its children (`here`) for these commands.

## Sort and views

At the title line's right (and in the selection bar, around "✕ n
selected") are **Sort ▾**, the view switch and **Details**.

- **Sort ▾**: a 232-wide menu listing Type, Name, Modified, Modified By and
  File size, then a divider, Ascending and Descending. Ticks show the current
  choice; when nothing has been chosen, nothing is ticked. Teams asks
  SharePoint for the folder again with `SortField={field}&SortDir=Asc|Desc`.
  Folders stay first. The choice lasts while you move between folders.
- **The column headers** (Name, Modified, Modified By, File size) have a
  chevron. Clicking one opens Ascending, Descending and Column settings ▸. The
  sorted column shows a 12 px ↑ or ↓ (#605E5C) after its name.
- **The view switch** offers List, Compact List and Tiles, each with its
  glyph. A tick shows the current one, and the button shows its glyph.
  - **Compact List** keeps List's columns, but rows are 34 tall with 20 px
    icons.
  - **Tiles** drops the white card. Cells are 176 x 171 and 8 apart,
    starting 12 below the title line.
    - Folders come first. Each is a 112 x 80 folder drawing with the number of
      items (14 px #8F3900), and the name and date centred under it (14 px,
      117 and 141 down).
    - Files start a new row 40 lower. Each shows its 74 x 96 picture with the
      app's badge, and the name.
    - Hover gives a white card (radius 12, shadow) with the selection circle
      at the top right.
    - OneDrive's FolderCover signal (its tiles' bundle; measured on
      testpc1 2026-11-27): a shared folder or a shortcut carries the 16 px
      People glyph in the count's shade 7 in from the folder drawing's
      bottom right corner. A shortcut also carries the shortcut badge
      (odsp-media `shortcutbadge_20.svg`, `_dark` in dark), 20 px, 10 past
      that corner. (OST's drawing, the 32 px folder icon at 112, spans 7 to
      105 across and ends 78.5 down, so the glyph sits at (82, 56) and the
      badge at (95, 68.5).) The Shortcuts folder
      is the blue company folder with its building glyph in that place and
      the count in #032F54.
- **Details** with nothing selected opens the current folder's pane
  (`docs/spec/details-pane.md`). The button shows pressed while the pane is
  open.

OST sorts in the app, on the same fields, with folders first. File pictures
in Tiles are Graph's "medium" thumbnails.

### Column headers and Column settings (TASK-0189)

Measured on winpc on 2026-11-19 (OneDrive's spartan list,
odsp-web-prod_2026-11-06.005), in a 1212 wide frame.

- Each header opens OneDrive's menu (232 wide, rows 36), in its own words:
  - Name: Ascending, Descending, then Column settings ▸;
  - Modified: Older to newer, Newer to older, Filter by, Column settings ▸;
  - Modified By: A to Z, Z to A, Filter by, Column settings ▸;
  - File size: Smaller to larger, Larger to smaller, Column settings ▸;
  - Sharing: Column settings ▸ alone. Activity has no menu.
- Column settings ▸ has only **Widen column** and **Narrow column**: the
  column's width (whole pixels) plus or minus 32. Teams has no show/hide or
  move here.
- Each boundary from Name|Modified to Sharing|Activity has a 16 x 36 resize
  divider, 8 below the header's top and centred on the edge (ew-resize). On
  hover it shows a 1 px #605E5C line, 28 tall. A drag sets the width of the
  column to its left.
- The widths you set are kept on this device only, in the SharePoint page's
  local storage: key `spcolumnsize-unsaved-{viewId}`, value
  `{"<column name>": "<px>"}`. Nothing goes to the server. They apply to
  every folder of that library's view.
- A column is never narrower than its responsive width: Narrow below it, or
  a drag past it, is stored but doesn't show. Wider columns make the grid
  scroll sideways.
- The responsive widths are OneDrive's `ODBMyFilesResponsiveBehavior` laid
  out by its module 4377:
  - min-max: DocIcon 40-40, Name 210-800, Modified 130-200, Modified By
    130-260, File size 85-110, Sharing 75-110, Activity 113-550;
  - too narrow: columns drop by priority (Sharing, File size, Activity,
    Modified By, Modified);
  - spare width is shared evenly up to each maximum, then among all but
    DocIcon;
  - at a 1212 frame: 40, 213.6, 133.6, 133.6, 88.6, 78.6, 116.6.
- OST draws the same menus and widths. It keeps your widths in the device
  setting `oneDriveColumnWidths` by library and column name. Harness
  `--column-settings-test`.

### Filter by (TASK-0236)

Measured on winpc on 2026-11-20 (Teams' OneDrive app, My files,
odsp-web-prod_2026-11-06.005).

- Modified and Modified By have **Filter by** in their menus; once that
  column is filtered it reads **Filter by (N)**, ticked, and the header shows
  a funnel after its name.
- Filter by opens a pane on the right: 340 wide, full height, white, Fluent's
  depth-64 shadow. Its title "Filter by '<column>'" (20/600 #616161 at
  24,20) gains " (N)" while N values are ticked. Close (32 px) sits 30 from
  the right. A click outside closes it.
  - Modified By: a people box "Enter a name or email address" (290x34 at
    25,50), then **@Me** (a 32 row), then each person who modified something
    in the folder (40 rows, 24 px pictures). The box asks SharePoint's
    `ClientPeoplePickerSearchUser` on each keystroke (QueryString, 30
    suggestions, PrincipalType 13, PrincipalSource 15, UseSubstrateSearch,
    no e-mail addresses). Suggestions: 260 wide, 54 rows, 40 px pictures. A
    picked person is added to the list, ticked, and the box empties.
  - Modified: the folder's distinct dates, M/D/YYYY, 32 rows.
  - The values come from `POST …/RenderListFilterData?FieldInternalName=
    'Editor'|'Modified'&RootFolder=…` plus the filters already set; its reply
    is an HTML `<SELECT>` (base64) whose `<OPTION Value>`s are the values
    (dates as YYYY-MM-DD).
  - **Apply** (80x32, primary once something changed) and **Clear all**
    (84x32) sit 16 from the bottom. Clear all only unticks; nothing changes
    until Apply, which closes the pane.
- The list is asked again (`RenderListDataAsStream`) with
  `FilterField1=Editor&FilterValue1=<name>&FilterType1=User` for one value,
  `FilterFields1=…&FilterValues1=a;#b&FilterTypes1=…` for several, a date as
  `FilterField1=Modified&FilterValue1=2026-11-11&FilterType1=DateTime&
  FilterDisplay1=11/11/2026`; columns are numbered in column order (Modified
  1, Modified By 2). With @Me there are no such parameters: the body carries
  `OverrideViewXml` `<View><Query><Where><Or id="Editor">…</Or></Where>
  </Query></View>`, values in the order ticked, @Me as `<UserID/>`.
- A bar above the header (42.67 tall, from x 25) shows "Modified:" /
  "Modified By:" (14, #424242) and a chip per value: 24 tall, radius 12, a
  24 px picture for a person, 13.33 px text ("[Me]" for @Me), an X that
  removes it. A **Clear** pill (22 tall, 1 px border, radius 12) at the right
  removes every filter.
- OST does the same (OneDriveView.qml's pane, chips and menus;
  `api::list_rows` filter_request / filter_values / filter_people; the
  backend keeps the folder's filters until another folder opens). Its words
  are OneDrive's (`x.odsp.*` ids, TASK-0233). Harness `--filter-by-test`.

## Home, Shared and People (TASK-0304, TASK-0320)

Teams' OneDrive app draws Home, Shared and a person's files with OneDrive's
newer ("Spartan") list, not the files table. Measured on winpc on
2026-11-26, from the list card's left edge:

**Home**
- "For you" (18, 600) at 8,29, then the cards from y 70. They come from
  `{personal}/_api/sp.RecentFileCollection.GetRecommendations` (verbose
  OData; with `prefer: useSmartCache`, as OneDrive's prefetch sends it, the
  service answers from a cache without the Loop and Whiteboard cards). Its
  `d.GetRecommendations` is JSON text, and the
  cards are in `EntitySets[0].ResultSets[0].Results`. Loop files kept in a
  Loop workspace (a `contentstorage` container) are left out. See
  `src/api/recommended.rs`.
- A card is 312 x 202.33: padding 16, radius 4, a 0.67 #F0F0F0 rim, 16
  apart. From a 1464 px strip the cards are 354 wide. The strip shows
  `clamp(floor((width + 16) / (tile + 16)), 3, 8)` cards and scrolls
  sideways.
  - The app icon (20) and the title (14, 600) sit over a 0.67 #EBEBEB rule
    at 52.67.
  - The badge is a 24 px circle (#E9EAF6, a 12 px #5B5FC7 glyph) or the
    person's picture. Its glyph is "view" for recently opened, "edit",
    "share", "comment" and so on; frequently opened and the rest use
    OfficeCatchUp.
  - The reason is 14/20 on two lines at most, the person's name in 600. The
    day ("17m ago", "Yesterday", "Mon") is 12 px #5E5E5D.
  - The button sits at 16.67,155.67 (30 tall, radius 4, a #D1D1D1 rim,
    14/600). An activity link (`NavigationInfo.Id`) gives Go to comment, Go
    to task or Watch recording. Otherwise Summarize (with a sparkle, radius
    6) or Recap this meeting, when Copilot is on and the badge is meeting
    preparation or "shared with you" by someone else, for files Copilot can
    read. Otherwise Open.
  - The picture box is 113.33 square at the right (#FAFAFA, #EBEBEB rim,
    radius 4). It shows the file's picture, or its 40 px icon for Loop,
    OneNote and Whiteboard.
- Recent's rows (OneDrive's RecentDataManager, file browser bundle
  2026-11-13): the recent service's top files
  (`sp.RecentFileCollection.GetRecentFiles?top=40`, `prefer: useSmartCache,
  filetypes="Word,Excel,PowerPoint,OneNote,Pdf,Video,Visio,Fluid,Playlist,
  Whiteboard,Lists"`), then DeltaSync's (`DeltaSync?top=500`), each file once
  by its `Id`, through the same `isInvalidOdbRecentItem` and newest opened
  first. The top files hold some DeltaSync leaves out: a chat's Loop notes
  (`loop_loopThread`, in its chat's container: Location
  `IC3_TeamsContainerType_…`, Owner SharePoint App) and a recap's
  Highlights pages (Location Meeting Artifacts). Checked as ost-test1 on
  2026-11-27: Teams' Home on testpc1 shows both loop_loopThread rows and
  both Highlights rows; OST's now does too (`recent_files::merge_home`).
- "Recent" (16, 600) at 8,310. Then the pills, from 67: All, Word, Excel,
  PowerPoint, PDF and More, 8.33 apart. They are 32 tall and round, with a
  0.67 #D1D1D1 rim; a picked pill is #E9EAF6 with a #5B5FC7 rim. All is
  text, the types are 45 wide with a 20 px brand icon, and More (the filter
  glyph) is 49 wide.
  - More ▾ (a 180 wide menu, 32 tall checkable items) holds OneNote, Lists,
    Videos, Loop, Whiteboard, PowerBI, Markdown and HTML. More looks picked
    while one of them is.
  - Pills add up; All clears them. They match OneDrive's type for the file
    (`Visualization.Type`), and Markdown and HTML by extension.
- "Filter by name or person": 240 x 32 at the card's right edge (16 px
  text). It matches the name, the owner and the activity.
- The list card starts at 360.

**The list** (Home, Shared ▸ With you, a person's files)
- A 45 px selection column, then OneDrive's responsive columns
  (`recentResponsiveBehavior` / `swmResponsiveBehavior`): Name 300-500 and
  growing, Opened or Date shared 130-200, Owner or Shared by 130-260,
  Activity 113-550. They are laid out over the card less 8.33 and the 45
  px column. At 876 they come to 337.42 / 167.42 / 167.42 / 150.42.
- The header is 48 tall (14, 600, text at 8). Rows are 56 tall with a 0.67
  #F0F0F0 rule.
  - Name: the 32 px icon at 8,11, the name (14) at 56,10, and the place
    line (12, #5E5E5D) at 56,29: My Files, "OST Test 3's Files", or the
    site. The place line opens the folder.
  - The dates and people are 14 px #5E5E5D.
  - Activity: the glyph at 18, then the person's name (600) and the rest at
    38, on two lines of 14. The day falls on a third line, which the 56 px
    row cuts off, as in Teams.

**Shared**
- The tabs "With you" and "By you" (18, 600; the picked one has a 2 px
  #5B5FC7 underline) sit at 0,25.
- With you has pills from 180: All, Folders, Word, Excel, PowerPoint, PDF
  and More (OneNote, Lists, Videos, Loop, Photos, Whiteboard, PowerBI,
  Markdown, HTML, Agent, Hidden). Hidden shows the files you hid from Shared.
  The filter box is at the right, and the card is at 76.
- The columns are Name, Date shared, Shared by and Activity. There is no
  File size or Sharing.
- By you is `{personal}/_api/web/onedriveshareditems?$top=1000` (odata
  verbose), in the service's order. Its columns are Name (with the place
  line) and Modified by (the editor), at 42 : 58 of a grid at least 1024
  wide. It has no pills and no filter box.

**People**
- "People" (18, 600) at 16,30 and "Filter by person" (200 x 32) at the
  right. The rows are on the page, with no card.
- Rows are 65 tall, with a 0.67 rule (5% black) between them. The 40 px
  picture is at 23 and the name (14) at 79, in a 320 cell.
- The person's files are chips from 336. A chip (OneDrive's filePill) is 40
  tall with a clear 1 px rim, radius 6, shadow 2, and 12 apart.
  - It has the 16 px icon, the name (12 px), and the activity pill (#F5F5F5,
    24 tall): the share glyph and the day in 10 px.
  - OneDrive fits them by characters × 5.2 + 64 + the pill
    (characters × 5.2 + 32). It starts at 50 and fits within the row's width
    less 64, 320 and 8.
  - The next file is shortened if 8 characters fit, then a "+n" chip (32
    wide) stands for the rest.

**Column menus, page scroll and Copilot (TASK-0340, winpc 2026-11-26)**
- Shared ▸ With you: Name ▾, Date shared ↓ ▾ and Shared by ▾ open OneDrive's
  sort menu, 240 wide at the column's left, 36 px items with the check at 8
  and the words (14 px #424242) at 32: A to Z / Z to A (Name, Shared by),
  Older to newer / Newer to older (Date shared). The list starts as the
  service gives it, Date shared newer to older; the sorted column shows
  ↑ / ↓. By you's and Home's headers have no menus.
- Home scrolls as one page: OneDrive's main area is the scroller, so For
  you, Recent's pills and the list go up together; the list is as tall as
  its rows.
- For you ▸ Summarize opens OneDrive's Copilot pane over the files: its own
  page `{your OneDrive}/_layouts/15/chat.aspx?app=OneDriveForBusiness&
  chatodsp={sdk, messaging {origin, channelId, identifyParent}, authentication
  {tokens…}, telemetry}` in a 400 px card, 12 from the top and bottom and 16
  from the right. Its host (Teams' OneDrive; OST's OdspCopilotPane) frames it
  from a page of the same SharePoint origin and talks OneDrive's SDK
  messenger: identify-parent, initialize (with a port), activate; then
  command / acknowledge / result. The host sends showView "chat",
  updateInstruction, updateHeader (Close shown), updateDataSources (the
  file's uniqueId, listId, webId, siteId, fileName, size, creation time and
  extension), updateChatInput ('Ask a question about "<file>"'),
  updateCustomPrompts and setPrompt 'Summarize "<file>"' with autoSubmit;
  the page asks the host for tokens (fetchAuthToken {type, resource}).

## Folder icon marks and Copilot ▾ (TASK-0358, measured on testpc1 2026-11-27)

- OneDrive's colored folder icon (module 4852) carries the People glyph when the folder is shared (`PrincipalCount` > 0) or is a shortcut: 12 px, 5 from the right and 8 from the foot of a 32 px icon (7 px bold, 3 and 6, at 20), in the folder colour's `countOverlay` shade (#8F3900 for yellow).
- A shortcut (Add shortcut to My files, ProgId `AddToOneDrive.MountPoint`) also carries OneDrive's shortcut badge, its odsp-media `images/addtoonedrive/shortcutbadge_12.svg` (`_dark` in dark), 12 px at the icon's corner (4 px past it at 20). OST loads it at run time. Its Sharing cell starts with ArrowSquareUpRight before "Owner: …".
- My files' header (and a My files subfolder's bar, after Copy link) has "Copilot ▾" (102.8 x 32, 206 from the title's start): the Copilot glyph (the colored odsp-media picture on hover), "Copilot" 14 px #616161, a 12 px chevron. Its menu has "Ask a question" (ChatSparkle 20), which opens the Copilot pane with no file: OneDrive sends updateChatInput (empty), the zero-query prompts "Summarize (file)", "Tell me about [a topic from my files]", "Find recent files on [a project]" and clearInputAreaText. (OneDrive also sends its knowledge agent state, which OST leaves out, as for Summarize; see below.)
- **The knowledge agent** (TASK-0372): with your OneDrive's page context saying `isKnowledgeAgentEnabled` (true for ost-test1), Teams' OneDrive answers the page's `request-tool-registration` with `registerRemoteTools` (the tool schemas its knowledge agent runtime, loaded from `kaToolsUrls`, defines) and then sends `updateKnowledgeAgentState` {scenario "OneDriveForBusiness", kaToolsUrls, kaToolsDevMode, webUrl, webTitle, listTitle, sharePointIds {siteId, webId, listId}, eligibleCodeModePrimitives (about a hundred: files.read, email.send, automation.*, …), currentPivot}. Copilot then answers with `request-tool-invocation` of `execute_plan`: JavaScript it wrote, which the host runs in a sandbox against those primitives (`toolCallBatch` / `result`), reporting `codeModePrimitiveProgress` and `completeToolInvocation` (captured on winpc 2026-11-26). OST doesn't host that runtime, so it doesn't announce the state: without the tools behind it, the page would plan tool calls nobody runs. OST answers `request-tool-registration` as unsupported, and Copilot answers from the chat's own grounding, as it does in OST today.

## Not yet in OST

- Add shortcut ▸, Version history and a folder's Request files: TASK-0115 and
  TASK-0116. They are left out of the bar, as they are of the item menu.
- Download of several items or a folder. Teams makes one zip with OneDrive's
  media service (`{mediaBaseUrl}/transform/zip`); OST saves each file on its
  own. Both are in TASK-0116.
- The Modified By name's profile card on click.
