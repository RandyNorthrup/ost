# File preview (Teams' Files apps)

What Preview does in Teams' OneDrive app and channel Files. Teams shows it
inside OneDrive's frame (`filebrowser.aspx`). OST draws it natively in
`desktop/qml/FilePreview.qml`.

Measured on winpc on 2026-11-12, in a 1212 x 632 frame, on ost-share-test.txt
and ost-open-test.docx.

## Opening it

- You open it from the item menu's **Preview**, which comes after Open ▸ for
  files.
- The viewer covers the whole frame. A `rgba(0,0,0,.4)` backdrop lies under a
  `rgba(31,31,31,.88)` layer, with the list still dimly visible through them.

## The top bar

The bar is 48 tall. Its glyphs and text are #F3F2F1.

- **Left**, 32 x 40 each, at 10, 46 and 82: "Download this file to your
  device", "Favorite this file" (the star) and "Delete this file". Then a
  divider, then "Info, View file details" (32 x 32 at 142, which opens
  Details) and More (···, at 178).
- **Centre**: the file's 16 px type icon and its name (14 px #F3F2F1, re-measured 2026-11-19).
- **Right**:
  - your picture (32 px, with a presence ring);
  - "Show comments" (text files only);
  - **Open ▾** (101.36 wide; the file's app icon for Office files);
  - **Share ▾** (102.01 wide);
  - **Close** (32 x 40 at 1166).
  - Show comments, Open ▾ and Share ▾ are 32 tall, radius 6, with a 0.67
    #808080 border on `rgba(31,31,31,.88)`, in white 14 px.
- **Previous and Next**: 40 px circles at the left and right edges, halfway
  down. They step through the other files in the list, and each has a
  tooltip ("Previous", "Next").

## The content

- **Text files** are read with SharePoint's
  `GET {site}/_api/web/GetFileById(guid'{id}')/OpenBinaryStream`. They are
  shown on a white page 909 wide (75%), from 45 down to the bottom:
  - a 30 tall strip with the name (14 px #242424);
  - the text in Consolas 14/19, with line numbers (the Monaco editor,
    read-only).
- **Word, Excel and PowerPoint** files show Office for the web's viewer
  (`doc.aspx?action=embedview`, which loads `wordviewerframe.aspx` in its own
  frame):
  - the page or pages on the dark layer;
  - a status line along the bottom: the app icon, "PAGE 1 OF 1" and the
    zoom ("100%").

## OST

- Text files are shown as Teams shows them.
- Images are shown fitted to the window, on the dark layer.
- **Office files.** OST doesn't embed web viewers. It asks Graph for the
  file as a PDF (`/drives/{d}/items/{i}/content?format=pdf`) and draws its
  pages natively with QtQuick.Pdf, under the same status line ("PAGE {n} OF
  {count}", the zoom). PDFs are drawn the same way.
- Files with no preview show "No preview available" (OST's wording, not yet
  captured from Teams), with Open ▾ and Download.
- The bar works as Teams':
  - **Download**, **Favorite**, **Delete** (with OneDrive's "Delete?"),
    **Details** (closes the viewer and opens the Details pane) and **More**
    (OneDrive's ···, below).
  - **Open ▾** lists the item menu's Open entries.
  - **Share ▾** lists Share, Copy link and Manage access, as Teams' does
    (below).
  - The arrow keys and the ‹ › buttons step through the folder's files.
    Escape closes.
- Not yet: the live presence of other people viewing the file (OST shows
  only your own picture).

## The bar's details, Show comments and narrow widths (TASK-0190)

Measured on winpc on 2026-11-19 on ost-share-test.txt.

- Glyphs, and the Open / Share labels, are #0078D4; the chevrons are white.
- **Show comments** is a 32 x 32 icon button (the comment glyph), between
  your picture and Open ▾. Its tooltip reads "Hide comments" while its pane
  is open.
- **The comments pane**: 370 wide, 8 in from the right, from 53 to 8 above
  the bottom; #141414, radius 5.
  - "Comments" (20/600 #F3F2F1) at 20, 26.6, and Close comments (32 px) at
    the right.
  - The "@mention or comment" box: 328 x 30.67, #252423, 0.67 #424242, a
    2 px #BEBBB8 bottom, radius 6.
  - The comments (SharePoint's `GetComments()` with the first ten replies),
    or OneDrive's empty state: its 128 px picture, "No comments yet" (16/600)
    and "Be the first to add a comment to the file" (14/20, 138 wide).
  - The page then takes 75% of the room left of the pane.
- **Share ▾**: a dark Fabric callout (#1B1A19, radius 4, 180 wide, padding 4)
  under the button, its right edge 8 in from the frame's: Share, Copy link,
  Manage access. Rows are 172 x 36, the 16 px glyph at 8 and the label at
  32, #F3F2F1.
- **···**: Copy to, Embed, Version history, Help ▸ (Send feedback, View
  tutorial). Embed opens OneDrive's "Embed" dialog:
  - 598.67 wide; 'Embed "{name}" on a blog or webpage.';
  - the file as embed.aspx shows it (550.67 x 212);
  - the code, `<iframe src="{site}/_layouts/15/embed.aspx?UniqueId={id}" width="640" height="360" frameborder="0" scrolling="no" allowfullscreen title="{name}"></iframe>`;
  - Copy embed code and Close.
- **Narrow**: going narrower, the left buttons fold into ··· one at a time:
  Info under 796, Delete under 760, Favorite under 724, Download under 688
  (Fabric's command bar; it comes back about 2 px wider). The name stays
  centred between the left buttons and the right group (60 clear of each).
- **640 and narrower**: the name from 8 (the width less 210), then ··· (W -
  200), Share ▾ (W - 160) and Close (W - 46). Your picture, Show comments and
  Open ▾ go: ··· then lists Download, Favorite, Delete, Info, Copy to,
  Embed, Version history, Help ▸, Show comments (a glyph without words, as
  Teams draws it) and Open ▸.
- OST draws all of this; Help ▸ Send feedback opens OST's feedback form
  (GitHub). Harness `--preview-bar-test` (with `--size` and
  `--preview-comment=<text>`).

Harness: `--preview-test`. It previews ost-share-test.txt as text, then
steps to ost-open-test.docx and shows it as PDF pages.
