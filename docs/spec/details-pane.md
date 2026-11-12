# Details pane (Teams' Files apps)

What the Details pane shows in Teams' OneDrive app and channel Files. Teams
draws it with OneDrive's own page (`filebrowser.aspx`) in a frame. OST draws
it natively in `desktop/qml/DetailsPane.qml`, with data from
`src/api/item_details.rs`.

Measured on winpc on 2026-11-12 (OneDrive build
odsp-web-prod_2026-10-30.004), on `ost-share-test.txt` in OST Test 1's My
files. Sizes are CSS px in a 1212 x 632 frame.

## Opening it

You open it from the item menu's **Details**, or from the command bar's
**Details** while one item is selected. It opens at the right of the list,
304 wide, starting under the command bar (76 down). It scrolls as one
column. Its sections are white cards on the page's #FAFAFA, about 12 apart.

While the pane is open, the list becomes narrow. Each row is then two lines:
the name over "Modified by {name} · {size}", with Modified on the right and
the hover ··· after the name. The list is 555 wide in the frame, against 874
without the pane.

## Sections

1. **Header**: white, 62.67 tall, padding 10 16.
   - The file's 20 px type icon at 16.
   - The name in 14/600 #616161, 28 after the icon.
   - **Options**: a 32 x 31.33 button with a 20 px ··· that opens the item
     menu.
   - **Dismiss**: a 24 px button with a 16 px ✕.
2. **Preview picture**: 304 x 180, white. It is the item's 320 x 180
   thumbnail
   (`{host}/_api/v2.0/drives/{d}/items/{i}/thumbnails/0/c320x180/content?prefer=noredirect,closestavailablesize`).
3. **Has access**: white, radius 4, padding 12 16.
   - "Has access" in 14/600.
   - A row of 32 px circles, 8 apart:
     - **Add people**: #5B5FC7 with a white 20 px person-add glyph. It opens
       the share dialog.
     - Each person with access, as their picture.
     - **Shared via link, manage access**: #D7D4D4 with a #444241 20 px
       link glyph. It shows when the item has links.
   - **Manage access** below, 12 px #3D3E66. It opens Manage access.
   - The data is SharePoint's `GetSharingInformation`.
4. **Activity**: white, padding 12 16.
   - **"All activity ▾"** (14/600, the brand colour) switches between **All
     activity** and **Comments** (a 232-wide menu with a check by the chosen
     one).
   - **The bell**: a 32 px switch with a 20 px brand bell, labelled
     "Notifications for item activity. Select to turn off notifications".
   - The comment box: 272 x 32, 0.67 #D1D1D1 border, radius 4, "Add a
     comment". It has Cancel (✕) and Submit comment (send) buttons, 32 each,
     with 16 px glyphs. Submit is #BDBDBD until there is text. A comment can
     be at most 2000 characters ("Maximum character limit exceeded"). Enter
     sends.
   - The activities, grouped. Each group has a 12/600 #424242 heading, 16
     tall, and 8 below it its cards:
     - #FAFAFA, radius 4, padding 14 16, 8 apart.
     - A 16 px brand glyph in a 32 box.
     - At 48: the text (12 px #616161; folder and file names in 600), and
       under it the time (10 px #424242, padding-top 2).
     - The time is SharePoint's `@sharePoint.localizedRelativeTime`, read
       like the list's Modified ("About a minute ago", "Yesterday at 10:37
       PM"). Its tooltip is "Nov 12 at 8:48 AM".
5. **More details**: white, radius 4, padding 16. Each row is the label
   (14/20 600 #424242) over the value (14/20 #616161), 12 apart:
   - **Type**: "txt File".
   - **Modified**: "11/11/2026 10:28 PM".
   - **Date created**: "11/11/2026 08:11 PM". The hour has two digits here.
   - **Path**: "My files › ost-share-test.txt". It has a 32 px "Copy direct
     link" button with a 20 px glyph after the label.
   - **Size**: "56 bytes".

## Activities

The list comes from
`GET {host}/_api/v2.0/drives/{d}/items/{i}/activities?$expand=driveItem($select=id,name,webUrl,parentReference,file,folder)&$top=25`
(the SharePoint token, Graph's shape). Each entry has an `action`, an
`actor.user` (`self` when it is you), `times.recordedTime` and
`@sharePoint.localizedRelativeTime`.

The kind is the first of these the action has: mention, comment (not a
reply), comment reply, create, archive, reactivate, delete, edit, move,
rename, restore, restoreVersion, share, version, copy. A restore (edit,
restoreVersion and version together) therefore reads as an edit.

OneDrive's wording in the pane, which is about one item, so the item is
"this file":

| Kind | Glyph | You | Someone else |
|---|---|---|---|
| edit | Edit | You edited this file | {name} edited this file |
| move (from) | MovetoFolder | You moved this file from **{folder}** | {name} moved this file from **{folder}** |
| move (to) | MovetoFolder | You moved this file to **{folder}** | {name} moved this file to **{folder}** |
| rename | Rename | You renamed **{old}** to **{new}** | {name} renamed **{old}** to **{new}** |
| share, no recipients | Share | You shared this file | {name} shared this file |
| share, to people | Share | You shared this file with {name} | {name} shared this file with you / with {name} |
| create | Add | You created this file | {name} created this file |
| delete | Trash | You deleted this file | {name} deleted this file |
| version | MovetoFolder | You created {version} of this file | {name} created {version} of this file |
| restore | Refresh | This file was restored | |
| comment | Comment | You commented / {name} commented, with the comment | |

- A move's folder is the last folder in `move.From`'s path ("Documents" for
  the library's top).
- Two or three people use "and" ("{1} and {2} shared this file"). More use
  "+ {n} others".
- The **Comments** view shows only comments. Comments come from
  `GET {site}/_api/web/lists(@a1)/GetItemById(@a2)/GetComments()` and are added
  with `POST …/GetItemById(@a2)/Comments()`. `CommentsDisabled` tells whether
  comments are allowed.

Groups, by the activity's time:

- **Today**, **Yesterday**.
- **This week**: since Sunday.
- **Last week**, **Two weeks ago**, **Three weeks ago**.
- **This month**, **Last month**.
- The month's name for earlier this year, or month and year for earlier years.
- **Older**.

## The bell

- The bell is on when the item's v2.1 `notificationPreferences` (from
  `GET {host}/_api/v2.1/drives/{d}/items/{i}/?$expand=notificationPreferences`)
  are all something other than "None". On this tenant it was `[{name:
  "Comments"}]`.
- Switching it posts `{site}/_api/web/ActivityLogger/FeedbackDirect` with:
  - `ListId`, `ListItemUniqueId`, `AffectedResourceUrl` and `ItemType`
    ("File");
  - `Operation`: "NotificationPreferenceChanged";
  - a `json` string holding `{"Scenario":"NotificationPreference",
    "NotificationPreference":"None"|"Comments", "Canvas":"DetailsPane", …}`.
- Checked on winpc: off and back on, ending on "Comments".

## The narrow list

While the pane is open, the list is 555 wide. Its columns are selection 56,
Type 40, Name 269.33 and Modified 189.33. Rows are 63 tall:

- The name is 14 px #616161, 14 down.
- Under it, 21.33 lower, is a 12 px #5E5E5D line: "Modified by OST Test 1 ·
  0 items". It is followed by the Sharing and Activity glyphs when there are
  any.
- The hover ··· sits after the name.

OST switches to this layout when the table is under 640 wide. That width is
not measured: OneDrive's actual breakpoint hasn't been found.

## Comments

- Comments come from
  `GET {site}/_api/web/lists(@a1)/GetItemByUniqueId(@a2)/GetComments()`.
  Each has `id`, `text`, `createdDate` and `author{name,email}`.
- In the feed a comment is its own card, in place of the comment activity:
  - the author's 32 px picture at 16;
  - at 64, "You" or the author's name (12 px), then the comment (12 px,
    padding 4 0 6), then the time in the client wording ("Just now",
    "8m ago");
  - your own comments have a 32 px brand "Show actions" ··· at the top right.
- Under each card is a "Reply" box (256 x 32, on white with padding 8).
- **Comments** shows only these cards. It reads "This item has no comments."
  when there are none.
- **Add:**
  `POST …/GetItemByUniqueId(@a2)/Comments()` with
  `{"__metadata":{"type":"Microsoft.SharePoint.Comments.comment"},"text":…}`.
  This returns 201.
- **Delete comment** asks "Delete comment" / "Do you want to delete this
  comment?" with Yes and Cancel, then sends `DELETE …/Comments({id})`.

## What OST does differently

- **The bell.** OST shows the bell's state and can turn notifications off.
  Turning them back on fails: SharePoint answers OST's token with "Failure :
  Action could not be performed." Teams sends the same request with cookies
  and a request digest, and that works. OST then shows the error and leaves
  the bell as it was (TASK-0122). SharePoint also leaves
  `notificationPreferences` out of some replies to OST's token; then OST
  treats the bell as on.
- **Change requires the site's ids.** `FeedbackDirect` needs `SiteId` and
  `WebId` in its `json`. OST reads them from `_api/site/id` and `_api/web/id`.
- **Comment features not yet in OST:** Edit comment, replies (the Reply
  box), likes and @mentions in comments (TASK-0121).
- **Pictures.** The 320 x 180 picture comes from Graph's
  `thumbnails/0/c320x180/content`.
- **Has access.** It lists the people with direct access, without the owner,
  from `GetSharingInformation`.

Harness: `--details-test [--details-live]`. The live run posts "OST test
112" on ost-share-test.txt, checks its card, then deletes it.
