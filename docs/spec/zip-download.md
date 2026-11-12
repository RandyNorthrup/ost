# Downloading a folder or several items (Teams' Files apps)

How Teams' OneDrive app and channel Files download a folder, or several
selected items, as one zip. Implemented in `src/api/zip_download.rs`, and
started from `FileActions.qml`. Captured on winpc on 2026-11-12 by
downloading ost-open-test.docx and ost-share-test.txt together. That zip was
deleted from winpc's Desktop afterwards.

## The request

OneDrive's page posts a form (`application/x-www-form-urlencoded`) to
`{.mediaBaseUrl}/transform/zip?cs={…}`, for example
`https://centralus1-mediap.svc.ms/transform/zip`. The reply is the zip
itself (`application/zip`). The browser saves it in Teams' download folder.

The form's fields:

- **`zipFileName`**: the one item's name plus ".zip" ("Notebooks.zip").
  Otherwise "OneDrive_{n}_{M-D-YYYY}.zip", where n counts up from 1 in each
  session ("OneDrive_1_11-12-2026.zip").
- **`guid`**: a new random id.
- **`provider`**: "spo".
- **`files`**: `{"items":[{"name","size","docId","isFolder"}]}`. Each
  `docId` is
  `{host}:443/_api/v2.0/drives/{drive}/items/{item}?version=Published&access_token=…`,
  using the library's drive access token.
- **`oAuthToken`**, **`pacToken`** and **`notificationUrl`**: only used for
  progress tracking and special policies. OST sends them empty.

`.mediaBaseUrl`, `.callerStack` and `.driveAccessToken` come from the list's
schema in SharePoint's `RenderListDataAsStream`. Only Teams' `RenderOptions`
value (5691143) returns them; 4 doesn't. The request has to carry Teams web's
User-Agent.

## In Teams and OST

- **Download** is in a folder's menu. The selection bar has it for several
  items. A single file still downloads as itself.
- The notices use OneDrive's strings:
  - while working: "Preparing {name} for download. This can take a moment.";
  - when done: "{name} was downloaded.";
  - on failure: "Couldn't download {name}. Try again.".
- OST saves the zip in the download folder (Settings ▸ Files and links'
  location, else `~/Downloads`).

Checked on linuxlt with `--zip-test`:

- `Notebooks.zip` held `Notebooks/OST Notebook/…`.
- `OneDrive_1_11-12-2026.zip` held both files and was 1257 bytes, the same
  size as the zip Teams made.
- Both test zips were deleted afterwards.
