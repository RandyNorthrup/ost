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
- **Centre**: the file's 16 px type icon and its name in 16 px.
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
    (the item menu).
  - **Open ▾** lists the item menu's Open entries.
  - **Share ▾** lists Share, Copy link and Manage access. Teams' Share ▾
    menu hasn't been captured yet.
  - The arrow keys and the ‹ › buttons step through the folder's files.
    Escape closes.
- Not yet: "Show comments" for text files, and the live presence of other
  people viewing the file (OST shows only your own picture).

Harness: `--preview-test`. It previews ost-share-test.txt as text, then
steps to ost-open-test.docx and shows it as PDF pages.
