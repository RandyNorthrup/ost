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
  yellow folder.
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
- **Details** with nothing selected opens the current folder's pane
  (`docs/spec/details-pane.md`). The button shows pressed while the pane is
  open.

OST sorts in the app, on the same fields, with folders first. Column settings
▸ isn't in OST yet. File pictures in Tiles are Graph's "medium" thumbnails.

## Not yet in OST

- The column headers' Column settings ▸.
- Add shortcut ▸, Version history and a folder's Request files: TASK-0115 and
  TASK-0116. They are left out of the bar, as they are of the item menu.
- Download of several items or a folder. Teams makes one zip with OneDrive's
  media service (`{mediaBaseUrl}/transform/zip`); OST saves each file on its
  own. Both are in TASK-0116.
- The Modified By name's profile card on click.
- Teams' Home view (For you cards; Opened, Owner and Activity from the recent
  files service) is a different layout. OST's Home still uses the files table.
