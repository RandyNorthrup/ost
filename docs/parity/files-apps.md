# Teams desktop parity: files, apps and embedded experiences

Scope: the new Teams desktop app for Windows (2025–2026). Each item says what Teams shows and what the user can do. Each embedded experience also has an `API:` line naming the documented service a native client could call. "none published" means no Microsoft-documented API for that function turned up in this research (Graph reference, Teams platform docs, Fluid docs).

Research notes:
- Sources were fetched from support.microsoft.com, learn.microsoft.com and fluidframework.com during 2026-11.
- The web-search budget ran out partway through. Later sources came from direct fetches of known URLs, so a few areas have thinner coverage. These are marked "(thin)".

---

## 1. OneDrive app (left rail; formerly "Files")

- [ ] Left-rail **OneDrive** icon: opens the OneDrive app inside Teams. Requires a OneDrive for Business account. Teams cannot connect to personal (consumer) OneDrive.
  Source: https://support.microsoft.com/en-us/office/explore-the-files-list-in-microsoft-teams-287ba970-2bdf-473d-a2da-76247ea4cf8f
  Source: https://support.microsoft.com/en-us/teams/files/file-storage-in-microsoft-teams
- [ ] **Home** view: files you recently viewed or edited.
  Source: https://support.microsoft.com/en-us/office/explore-the-files-list-in-microsoft-teams-287ba970-2bdf-473d-a2da-76247ea4cf8f
- [ ] **My files** view: all files and folders in your personal OneDrive for Business, with folder navigation.
  Source: same as above
- [ ] **Shared** view: files and folders shared with you, plus ones you created and shared.
  Source: same as above
- [ ] **Favorites** view: files you starred as favorites.
  Source: same as above
- [ ] **Recycle bin** view: files you deleted, available for restore.
  Source: same as above
- [ ] **Browse files by > People**: files grouped by the people they were shared between.
  Source: same as above
- [ ] **Browse files by > Meetings**: files grouped by the meeting they were shared in.
  Source: same as above
- [ ] **Browse files by > Media**: files grouped by media type.
  Source: same as above
- [ ] **Quick access** section: shortcuts to the file libraries of specific Teams channels. **More places...** browses further libraries.
  Source: https://support.microsoft.com/en-us/teams/files/move-or-copy-files-in-microsoft-teams
- [ ] Search and filter inside the OneDrive app ("you can search and filter files to find the ones you need").
  Source: https://support.microsoft.com/en-us/teams/files/file-storage-in-microsoft-teams
- [ ] **Create or upload** button:
  - **Files upload** picks a local file, and the upload starts automatically.
  - Choosing a file type, entering a name and selecting **Create** makes a new Office file that opens for editing.
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Per-item hover **Share** button, which opens the share dialog (see §4).
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
- [ ] Per-item **More actions** menu with these entries:
  - **Open in** (Teams / Desktop app / Browser)
  - **Open in OneDrive**
  - **Rename**: enter the name, then **Update**
  - **Move to** / **Copy to**: folder picker, then **Move here**
  - Download, Delete, Copy link
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/files/move-or-copy-files-in-microsoft-teams
- [ ] Multi-select: hover each row and tick the circled check mark in the left column. Bulk **Move to** / **Copy to** then applies to all selected items.
  Source: https://support.microsoft.com/en-us/teams/files/move-or-copy-files-in-microsoft-teams
- [ ] Open the OneDrive app in a separate window. Teams personal apps support "Open in new window", which can be checked per app.
  Source: https://support.microsoft.com/en-us/planner/teams/getting-started-with-planner-in-teams (generic "Open in new window" pattern)
- API: Microsoft Graph driveItem/drive API (v1.0) covers this app:
  - Listing: `/me/drive/root/children`, `/me/drive/recent` (Home), `/me/drive/sharedWithMe` (Shared), `/me/drive/following` (most likely what backs Favorites; not confirmed).
  - File operations: upload, rename/move (PATCH parentReference), copy, delete.
  - Recycle bin gap: no Graph v1.0 endpoint was found to list or restore the OneDrive for Business recycle bin. `driveItem: restore` is "currently only available for OneDrive Personal", and `recycleBin` list items targets SharePoint Embedded containers only.
  - The "Browse by People/Meetings/Media" groupings have no dedicated endpoint. They would need to be derived client-side from sharedWithMe/recent metadata.
  (https://learn.microsoft.com/en-us/graph/api/drive-recent, https://learn.microsoft.com/en-us/graph/api/drive-sharedwithme, https://learn.microsoft.com/en-us/graph/api/drive-list-following, https://learn.microsoft.com/en-us/graph/api/driveitem-restore, https://learn.microsoft.com/en-us/graph/api/recyclebin-list-items?view=graph-rest-beta, https://learn.microsoft.com/en-us/graph/api/driveitem-copy, https://learn.microsoft.com/en-us/graph/api/driveitem-move, https://learn.microsoft.com/en-us/graph/api/driveitem-delete)

## 2. Files in chats (attach, preview, Shared tab)

- [ ] Attaching from the compose box: **Actions and apps** > **Attach file**, which offers:
  - a list of recently opened files
  - **Attach cloud files** (OneDrive/SharePoint picker)
  - **Upload from this device**
  Source: https://support.microsoft.com/en-us/office/chat-and-share-files-in-teams-d7978db0-33b5-4ad3-93ac-ef0bd3c2a670
- [ ] Drag a file from the OS file manager into the message to attach it.
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
- [ ] Storage: files sent in 1:1 or group chat are uploaded to the sender's OneDrive, folder **Microsoft Teams Chat Files**. They are shared only with the chat members.
  Source: https://support.microsoft.com/en-us/teams/files/file-storage-in-microsoft-teams
- [ ] Large-file upload runs in the background with a progress indicator while you keep chatting. Message order may change after the upload completes.
  Source: https://support.microsoft.com/en-us/office/chat-and-share-files-in-teams-d7978db0-33b5-4ad3-93ac-ef0bd3c2a670
- [ ] Automatic attachment previews in the message:
  - image, video and many document types
  - with more than 3 attachments, the preview appears only after send
  - a single PDF or 3D file (GLB, STL, FBX, OBJ) previews inline, and the **Preview** button opens it inside the chat or channel
  Source: same as above
- [ ] No preview appears when:
  - you lack permission to the file
  - the file is encrypted with certain sensitivity labels; the user can request access instead
  - the chat includes external users
  - the type is unsupported, e.g. .zip
  Source: same as above
- [ ] Pre-send permission check: Teams checks whether recipients can open the attached file. If not, a banner on the file preview offers **Give access**, then **Update access** before sending.
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
- [ ] Attachment card **More attachment options**: Open in browser, Download, Copy link, and **Open in** > Desktop app / Browser.
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- [ ] Chat **Shared** tab at the top of every chat lists the files and links shared in the chat:
  - filter pills **Recent**, **Files**, **Links**
  - Copy link from the tab
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
- [ ] **Chat details** pane (top-right **Open Chat details**):
  - **Shared** section: click to open; **More options** to copy, download or view; **See all** jumps to the Shared tab
  - **People** section: up to 7 shown, plus **See all**
  - **Pinned messages**: up to 10
  - Available for 1:1, group and meeting chats
  Source: https://support.microsoft.com/en-us/teams/chat/show-chat-info-in-microsoft-teams
- [ ] Links in messages:
  - insert via **Format** > **Insert link** (display text plus address), or paste
  - Teams may truncate long URLs; **Ctrl+Shift+V** pastes without formatting
  - Safe Links (ATP) warns on unsafe links
  - opening a web link while signed in to Edge can open it side-by-side with the chat
  Source: https://support.microsoft.com/en-us/office/chat-and-share-files-in-teams-d7978db0-33b5-4ad3-93ac-ef0bd3c2a670
- API:
  - Upload into `Microsoft Teams Chat Files` with Graph upload sessions.
  - Grant chat members access with `driveItem: invite` (or `createLink` scope=users).
  - Send the message with a `chatMessageAttachment` of `contentType: "reference"` and `contentUrl` set to the file URL.
  - Inline previews: `driveItem: preview` (short-lived embeddable URL, so web-based), or native rendering via `/content?format=pdf|jpg` (conversion limited to files ≤ 2 MB) and `thumbnails`.
  - No documented API for the Shared tab aggregate. Derive it from message attachments.
  (https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession, https://learn.microsoft.com/en-us/graph/api/driveitem-invite, https://learn.microsoft.com/en-us/graph/api/resources/chatmessageattachment, https://learn.microsoft.com/en-us/graph/api/driveitem-preview, https://learn.microsoft.com/en-us/graph/api/driveitem-get-content-format, https://learn.microsoft.com/en-us/graph/api/driveitem-list-thumbnails)

## 3. Channel files (Shared tab / SharePoint library)

- [ ] Each channel has a SharePoint document library folder. Files uploaded to a channel go to the team's SharePoint site, and SharePoint and Teams stay in sync both ways.
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Channel **Shared** tab (older builds and docs call it **Files**):
  - **In Post**: files and links from posts, with **Recent** / **Files** / **Links** filters
  - **In library**: searches and browses the channel's SharePoint library
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
- [ ] Toolbar **New** creates: Folder, Word document, Excel workbook, PowerPoint presentation, OneNote notebook, Visio drawing, Forms for Excel, and a Link (to a website or file).
  Source: https://support.microsoft.com/en-us/teams/teams-channels/add-content-and-notes-to-a-team-in-microsoft-teams
- [ ] Toolbar **Upload**: file, folder or template. Drag-and-drop onto the file list also works. Uploaded files are accessible to every channel member.
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/teams-channels/add-content-and-notes-to-a-team-in-microsoft-teams
- [ ] **More commands** > **Sync**: syncs the library to the PC through the OneDrive sync client.
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] **More commands** > **Open in SharePoint**. The SharePoint **Details** pane > **Activity** is also where a renamed or deleted channel folder is reverted.
  Source: same as above
- [ ] Per-item **More actions**: **Rename** (dialog with **Rename** button), **Copy link** (with link settings), Move to, Copy to, Open in, Download, Delete.
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/files/share-a-file-to-multiple-channels-in-microsoft-teams
- [ ] Share one file to several channels by posting a link (reply > **More actions and apps** > **Attach file**). The post shows the name of the team and channel where the file is stored. There is no need to upload copies.
  Source: https://support.microsoft.com/en-us/teams/files/share-a-file-to-multiple-channels-in-microsoft-teams
- [ ] Keyboard and screen-reader path:
  - Posts tab, Right arrow to Files, Enter
  - Tab to **New**, Right arrow to **Upload**
  - row **Show actions** > **Open in app**
  Source: https://support.microsoft.com/en-us/office/use-a-screen-reader-to-work-with-files-in-microsoft-teams-d07f6711-c938-40ef-8201-cc98e0106f3f
- [ ] File as a tab: **Add a tab** > pick the file-type app (e.g. Word) > choose a file already shared in that chat or channel > **Save**. Microsoft 365 file types can then be co-edited in the tab.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
- [ ] SharePoint tab: **+** > **SharePoint** > Pages / Lists / Document libraries from the team site, or **Any SharePoint site** (paste a URL). You must be site owner to add team-site content.
  Source: https://support.microsoft.com/en-us/sharepoint/libraries/add-a-sharepoint-page-list-or-document-library-as-a-tab-in-teams
- API:
  - `GET /teams/{id}/channels/{id}/filesFolder` returns the channel's driveItem. Some special characters in channel names make it error.
  - Then the standard drive API: children, upload, createLink, delta for sync.
  - Library Sync is the OneDrive sync client; a native client could implement its own with `delta`.
  - SharePoint page tabs have no native-render API; page content via Graph sitePage is outside this research.
  (https://learn.microsoft.com/en-us/graph/api/channel-get-filesfolder, https://learn.microsoft.com/en-us/graph/api/driveitem-delta)

## 4. Share dialog and link settings

- [ ] Hover a file > **Share** opens the share dialog with:
  - **Copy link** (link pasteable in chat or email)
  - **Sharing settings** / **Link settings** (gear)
  - recipients box for name, group or email
  - permission dropdown and optional message
  - **Share** / **Send**
  Source: https://support.microsoft.com/en-us/teams/files/share-files-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Permission dropdown options:
  - **Can edit** (default)
  - **Can review**: suggest changes but not edit directly
  - **Can view**
  - **Can't download**
  Source: same as above
- [ ] Link audience options:
  - **People in your organization with the link can edit** (typical default label)
  - **People you choose**: needed for people outside the org; then **Apply** and add emails
  - Anyone, and People with existing access (OneDrive dialog)
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/onedrive/share-files-and-folders-in-microsoft-onedrive
- [ ] Extra link options in the OneDrive/SharePoint dialog:
  - **Block download** (work/school only, view links only)
  - **Set expiration date**
  - **Set password** (Anyone links; folders only on Anyone links)
  Source: https://support.microsoft.com/en-us/onedrive/share-files-and-folders-in-microsoft-onedrive
- [ ] **Change** link (from Copy link) edits who the copied link works for.
  Source: https://support.microsoft.com/en-us/teams/files/share-a-file-to-multiple-channels-in-microsoft-teams
- [ ] **Manage Access**: see existing links and who has access.
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- API: Graph `driveItem: createLink` and `driveItem: invite`, plus `driveItem: list permissions` / delete permission.
  - createLink v1.0: type `view` | `edit` | `embed`; scope `anonymous` | `organization` | `users`; expirationDateTime; `password` documented as OneDrive Personal only in v1.0.
  - createLink beta adds type `review`, `blocksDownload`, `createOnly`, `addressBar` and `adminDefault`, plus `password`, `recipients` and `sendNotification`. These cover "Can review", "Can't download" and specific-people links, but are beta only.
  (https://learn.microsoft.com/en-us/graph/api/driveitem-createlink, https://learn.microsoft.com/en-us/graph/api/driveitem-createlink?view=graph-rest-beta, https://learn.microsoft.com/en-us/graph/api/driveitem-invite, https://learn.microsoft.com/en-us/graph/api/driveitem-list-permissions)

## 5. Opening, viewing and editing Office files inside Teams

- [ ] Open a file from three places: the OneDrive app list, the Shared tab of a chat or channel, or the message the file was attached to. By default it opens inside Teams with the standard Office ribbon at the top.
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- [ ] **Settings and more** > **Settings** > **Files and links** > **File open preference** dropdown: **Teams** / **Desktop app** / **Browser**. Applies to Word, PowerPoint and Excel, and saves automatically.
  Source: same as above
- [ ] One-off override: right-click or **More actions** > **Open in** > **Desktop app** / **Open in browser**. Teams on the web offers Teams / Browser instead.
  Source: same as above
- [ ] Desktop-app editing requirements: Teams desktop (Windows/macOS), an Office 365 E3/E5 license and Office 16+. Linux users can't open the desktop Office apps and must use Office for the web.
  Source: same as above
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Header actions in the in-Teams file viewer:
  - **Comments**
  - **Catch up**: changes others made since your last view
  - **Editing** mode switch: Editor (default) or Reviewer
  - **Share** submenu: Share, Copy Link, Manage Access; plus **People in your organization with the link can edit** settings
  - **Close**: returns to where you were in Teams
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- [ ] Tab conversation while viewing a file or tab: **Show tab conversation** toggles a side discussion. Replies are posted as replies to the original channel post.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
- [ ] Non-Office files must be edited in their own apps and re-uploaded. On mobile, editing happens in the Office mobile apps.
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- API, viewing: Graph `/content?format=pdf` (or `jpg` with width/height) for native rendering. Format conversion is limited to files ≤ 2 MB. Larger files need `driveItem: preview`, which returns a short-lived embeddable URL (web).
  (https://learn.microsoft.com/en-us/graph/api/driveitem-get-content-format, https://learn.microsoft.com/en-us/graph/api/driveitem-preview)
- API, editing in-app: none published for a native client. Office for the web editing is reached only by embedding it (WOPI host integration is limited to Cloud Storage Partner Program members and needs Microsoft verification). For SharePoint-stored files the editor is SharePoint's own web frame.
  (https://learn.microsoft.com/en-us/microsoft-365/cloud-storage-partner-program/online)
- API, open in desktop app: Office URI schemes are documented, e.g. `ms-word:ofe|u|<https-url>` for edit, `ofv` for view, and the same for `ms-excel:` / `ms-powerpoint:`.
  (https://learn.microsoft.com/en-us/office/client-developer/office-uri-schemes)
- API, open in browser: open the driveItem `webUrl`. Native "Open in browser" needs nothing beyond Graph metadata.

## 6. Co-authoring, check-out and version history

- [ ] Co-authoring:
  - real-time multi-user editing of Office files opened in Teams, browser or desktop
  - presence avatars and Catch up in the viewer
  - editing Visio files requires a Visio license
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/teams/files/edit-a-file-in-microsoft-teams
- [ ] Version history:
  - in the Office editor: select the file title > **Version history**; a selected version opens separately; **Restore**
  - works only for files in OneDrive/SharePoint
  - the number of versions depends on library configuration (25 for personal accounts)
  Source: https://support.microsoft.com/en-us/office/collab-files/view-previous-versions-of-office-files
- API: Graph `driveItem: list versions`, `driveItemVersion: restore`, `checkout` / `checkin`. Live co-authoring content sync has no published API, since the Office co-authoring protocol isn't public. A native client can show versions and restore them, but can't co-edit without Office.
  (https://learn.microsoft.com/en-us/graph/api/driveitem-list-versions, https://learn.microsoft.com/en-us/graph/api/driveitemversion-restore, https://learn.microsoft.com/en-us/graph/api/driveitem-checkout)

## 7. Loop components in chat and channel posts

- [ ] Insert: compose box **Loop components** icon > choose a type > type content > **Send**. **/loop** in the compose box inserts a Loop paragraph. Contents are visible only to the author until sent.
  Source: https://support.microsoft.com/en-us/teams/apps-service/send-a-loop-component-in-microsoft-teams-chats
  Source: https://support.microsoft.com/en-us/teams/teams-channels/manage-pages-and-loop-components-in-channels
- [ ] Component types in the picker:
  - Bulleted list, Numbered list, Check list, Paragraph
  - Table, Voting table
  - Code
  - Kanban board, Task list, Progress tracker
  - Q&A Session, Team Retrospective
  The work-tenant docs list "paragraph, table, checklist, or other component". The full list of 11 comes from the Teams personal page; the other types also appear in Teams Free and Whiteboard docs.
  Source: https://support.microsoft.com/en-us/teams/personal/chat/send-a-loop-component-in-microsoft-teams-personal
  Source: https://support.microsoft.com/en-us/accessibility/loop/use-a-screen-reader-with-loop-components-in-a-chat-in-microsoft-teams
- [ ] Inline editing by every chat or channel member:
  - **/** inserts an @mention, date, image or nested component
  - **//** adds an attributed comment
  - **@** mention sends an activity-feed notification that deep-links into the component
  Source: same as above
- [ ] Presence and access controls:
  - colored live cursors
  - avatar stack upper-right for viewing, editing or recently edited; hover for details
  - **See who has access**: who can view or edit, plus people who have viewed
  Source: https://support.microsoft.com/en-us/teams/teams-channels/manage-pages-and-loop-components-in-channels
- [ ] Component header controls:
  - linked **file name** opens the .loop file in Loop/Office.com
  - **Copy component**: paste into another chat or channel with Ctrl+V; it stays live everywhere
  - **Copy link**
  - sensitivity label dropdown (top-left) > **Apply**
  Source: same as above
- [ ] Message actions: **More options** > **Pin** keeps the component at the top or in the info pane. **More options** > **Delete** removes the message but not the file.
  Source: same as above
- [ ] Keyboard: **Ctrl+Enter** sends the component; **Esc** leaves the picker; Tab or arrow keys move within the component.
  Source: https://support.microsoft.com/en-us/accessibility/loop/use-a-screen-reader-with-loop-components-in-a-chat-in-microsoft-teams
- [ ] Permissions:
  - defaults to org link permissions, but components are always shared editable even if the org default is view-only
  - with the "Specific people" default, group chats over 20 members need manual permission choice
  - creator needs a OneDrive license (otherwise no "Collaborate with Loop" option until Teams restarts after licensing)
  - guests can edit but not create
  - disabled in most federated chats
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-components-teams
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-admin-configuration
- [ ] Storage:
  - private chat: creator's OneDrive `Microsoft Teams Chat files`
  - channel: SharePoint channel folder (Shared Documents)
  - the file is `.loop` (older ones `.fluid`)
  - moving the file to another library breaks the component
  - restore via OneDrive version history
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-admin-configuration
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-components-teams
- [ ] Admin off (`Set-SPOTenant -IsLoopEnabled $false`, tenant-wide): the insert entry point is hidden and existing components render as plain hyperlinks that open the browser Loop editor.
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-components-teams
- [ ] Search in Teams returns a link to the component, not the containing message.
  Source: same as above
- API: none published for reading or editing Loop component content.
  - The `.loop` file is reachable as a driveItem (list, share, version, delete through Graph), but its content format is not documented.
  - Fluid Framework's `@fluidframework/odsp-client` is experimental and beta-only. It creates and opens the app's *own* Fluid containers in SharePoint Embedded/ODSP; nothing in the docs says it can open Microsoft Loop components.
  - A Microsoft Q&A request (Feb 2026) for a Loop content API was answered only with a pointer to the Feedback Portal.
  - Native fallback: render the hyperlink and open it in the browser, which is exactly Teams' own behavior when Loop is disabled.
  (https://learn.microsoft.com/en-us/microsoft-365/loop/loop-components-teams, https://fluidframework.com/docs/api/odsp-client/, https://learn.microsoft.com/en-us/answers/questions/5760312/can-ms-provide-a-microsoft-loop-api-for-programmat)

## 8. Channel Pages (Loop pages) and Loop workspace tabs

- [ ] New page: channel header **Add a tab** > **New page** > start typing. Works in standard, private and shared channels. Several pages per channel are allowed, and the first page is pre-provisioned.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/manage-pages-and-loop-components-in-channels
  Source: https://blog.topedia.com/2025/10/loop-pages-in-teams-channels-simplify-team-collaboration/ (third-party, for rollout details)
- [ ] Link an existing page:
  1. In Loop, use **Share** > **Page link**.
  2. In the channel, use **Add a tab** > **Existing page**, paste the link, then **Add page**.
  Pages in personal workspaces such as Copilot Pages can't be added.
  Source: same as above
- [ ] Share a page: right-click the page tab > **Copy link to tab**, then paste. Recipients need channel access.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/manage-pages-and-loop-components-in-channels
- [ ] Delete:
  - right-click the tab > **Remove** removes the tab only
  - deleting the content happens in SharePoint (More options > Delete, then the recycle bin)
  - pages live in the channel's **Shared** tab or SharePoint channel folder
  Source: same as above
- [ ] Page editing features (Loop editor):
  - "/" menu: table, checklist, bulleted list, numbered list, date, callout, code, table of contents, divider, task list, @mention
  - "//" comments
  - live cursors
  - sensitivity labels
  Source: https://support.microsoft.com/en-us/teams/teams-channels/manage-pages-and-loop-components-in-channels
  Source: https://support.microsoft.com/en-us/accessibility/loop/basic-tasks-using-a-screen-reader-with-microsoft-loop (from search summary; thin)
- [ ] Loop workspace tab (standard channels only):
  1. **+** > **Apps** > **Loop**.
  2. Name the workspace, then **Create**.
  - Membership mirrors the channel, team owners become workspace owners, and the label is inherited from the M365 group.
  - Several workspaces per channel are allowed. Re-adding the tab re-pins an existing workspace.
  - Rename only from the Loop web app. The workspace can't be deleted separately from the team.
  - Workspace invites and links are unavailable.
  Source: https://support.microsoft.com/en-us/loop/loop-workspaces-in-teams-channels
- [ ] Storage and policy:
  - channel pages are SharePoint-site files in the channel folder
  - channel workspaces are a shared SharePoint Embedded container, governed by cloud policy "Create Loop workspaces in Loop"
  - Teams chat notes are also SharePoint Embedded
  - each container is capped at 25 TB
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-admin-configuration
  Source: https://learn.microsoft.com/en-us/microsoft-365/loop/loop-storage
- API: none published for page or workspace content.
  - SharePoint Embedded containers expose metadata via Graph `fileStorageContainer`, which requires container-type permissions the Loop app owns.
  - Page files are reachable as driveItems, but the content is in an undocumented Fluid format.
  - Tab pin and unpin go through Graph `teamsTab`.
  (https://learn.microsoft.com/en-us/graph/api/resources/filestoragecontainer, https://learn.microsoft.com/en-us/graph/api/resources/teamstab, https://learn.microsoft.com/en-us/answers/questions/5760312/can-ms-provide-a-microsoft-loop-api-for-programmat)

## 9. Notes tab (OneNote) and OneNote app

- [ ] New standard channels get a **Notes** tab. It shows that channel's section of the team's default OneNote notebook, and replaced Wiki in 2023.
  Source: https://support.microsoft.com/en-us/office/manage-your-team-s-notes-with-onenote-13fd630e-cf97-4779-b94c-f8e55fdeb075
  Source: https://support.microsoft.com/en-us/onenote/export-a-wiki-to-a-onenote-notebook-in-microsoft-teams
- [ ] Notes tab capabilities:
  - rich editing: typing, ink annotation, highlighting, file attachments
  - search
  - **Show navigation** pane: sections and pages, **Add page**
  - recommended convention: one section per channel, named after the channel
  - standard channels only
  Source: https://support.microsoft.com/en-us/onenote/export-a-wiki-to-a-onenote-notebook-in-microsoft-teams
- [ ] Add a OneNote tab: **Add a tab** > **Apps** > **OneNote**, then one of:
  - **+ Create New Notebook** (name, then **Save**)
  - pick an existing notebook
  - **Paste a OneNote link** to a notebook, section or page
  Everyone in the channel can view and edit if they have notebook access. People blocked can **request access** from the tab. Only notebooks on SharePoint or OneDrive for Business are supported.
  Source: https://support.microsoft.com/en-us/teams/apps-service/add-a-onenote-notebook-in-microsoft-teams
- [ ] Restore a removed Notes tab: **Add a tab** > OneNote tile > default team notebook, or expand it to a section or page > **Save**. Rename a tab via right-click > **Rename** > **Save**.
  Source: https://support.microsoft.com/en-us/onenote/export-a-wiki-to-a-onenote-notebook-in-microsoft-teams
- [ ] Wiki retirement:
  - Wiki tabs and the Wiki app have been gone since Feb 2024; export ended then
  - .mht files remain in SharePoint **Site contents** > **Teams Wiki data**
  - private-channel wikis had no migration path
  Source: same as above
- [ ] OneNote personal app (left rail): notebook list with hover **More options** > **Open** (OneNote for the web) or the split arrow > **Open in desktop**.
  Source: https://support.microsoft.com/en-us/teams/apps-service/add-a-onenote-notebook-in-microsoft-teams
- API: Microsoft Graph OneNote API (v1.0), usable for a native Notes tab.
  - Reads and navigation:
    - list notebooks, section groups, sections and pages under `/me`, `/groups/{id}` or `/sites/{id}/onenote`
    - `GET pages/{id}/content` returns page HTML; `?includeIDs=true` adds IDs needed for updates
    - `pages/{id}/preview` gives a text snippet of up to 300 chars
    - 20 entries by default, max 100 per page
  - Create a page: POST HTML to `sections/{id}/pages`, using a constrained HTML/CSS subset with absolute-positioned divs, images, embedded files and PDF printouts.
  - Update a page: PATCH a JSON array of `{target, action: append|insert|prepend|replace, position, content}`. Targets come from `data-id` or generated IDs. Replacing `tr` and `td` is not supported (replace the whole table). Images must be sent inline, not as web URLs.
  - Delete page.
  - Limits:
    - app-only auth ended 31 Mar 2025, so delegated only
    - error 507 when a section reaches the page cap
    - queries fail when a library holds over 5,000 OneNote items
    - backup or restore of whole sections or notebooks is not a supported scenario
  - The HTML model is lossy relative to the OneNote canvas (layout and ink fidelity limited), so expect only partial-fidelity editing.
  (https://learn.microsoft.com/en-us/graph/integrate-with-onenote, https://learn.microsoft.com/en-us/graph/onenote-get-content, https://learn.microsoft.com/en-us/graph/onenote-create-page, https://learn.microsoft.com/en-us/graph/onenote-update-page, https://learn.microsoft.com/en-us/graph/onenote-input-output-html, https://learn.microsoft.com/en-us/graph/onenote-error-codes)

## 10. Whiteboard

- [ ] Entry points:
  - Whiteboard app in Teams (gallery)
  - **Whiteboard** tab in chats and channels (**+** > search Whiteboard)
  - meeting **Share** tray > Whiteboard section; this shares the meeting's existing board by default, or pick or create one
  Source: https://support.microsoft.com/en-us/whiteboard/getting-started-with-microsoft-whiteboard
  Source: https://support.microsoft.com/en-us/whiteboard/retirement-standalone-microsoft-whiteboard-apps
  Source: https://support.microsoft.com/en-us/whiteboard/share-a-whiteboard-in-microsoft-teams (from search summary; thin)
- [ ] Canvas UI:
  - Left: pointer or inking mode, and the **Create** panel (sticky notes, text, images, shapes, templates, Loop components, etc.)
  - Top center: 3 pens with color, thickness and arrow option; highlighter; eraser; lasso multi-select
  - Top left: **Home** (board picker), undo/redo, rename board
  - Top right: **Share** link; **Settings** for export to image, background format and Help
  - Ink beautification
  Source: https://support.microsoft.com/en-us/whiteboard/getting-started-with-microsoft-whiteboard
- [ ] After a meeting, the board stays in the meeting chat on a tab labeled **Whiteboard**. Only in-org participants can keep accessing it. Whiteboards aren't captured in meeting recordings.
  Source: https://support.microsoft.com/en-us/office/continue-working-on-a-whiteboard-after-a-meeting-5e0a4853-3a53-492b-97dd-c3e3ed0e7f09
- [ ] Loop components (Table, Checklist, Voting table, Progress tracker, Task list) can be inserted on the canvas.
  Source: https://support.microsoft.com/en-us/office/loop-components-in-whiteboard-c5f08f54-995e-473e-be6e-7f92555da347 (from search summary; thin)
- [ ] The standalone Whiteboard apps for Windows, iOS and Android retired on 16 Oct 2026. For work accounts, Whiteboard continues in Teams and on the web.
  Source: https://support.microsoft.com/en-us/whiteboard/retirement-standalone-microsoft-whiteboard-apps
- [ ] Storage:
  - boards are `.whiteboard` files in the creator's OneDrive, including those from meetings, chats and channels (SharePoint "not yet supported")
  - typical size 50 KB–1 MB
  - OneDrive retention, DLP, legal hold and basic eDiscovery apply
  Source: https://learn.microsoft.com/en-us/microsoft-365/whiteboard/manage-data-organizations
- API: none published for board content.
  - No Whiteboard resource exists in the Graph reference (the candidate pages return 404).
  - `.whiteboard` files can be listed, shared or deleted as driveItems, but the format is undocumented.
  - The WhiteboardAdmin PowerShell module (Global or SharePoint admin only) has `Export-WhiteboardHtml` and Fluid-whiteboard getters, which are admin tooling and not a client API.
  - Native fallback: open the board's web URL.
  (https://learn.microsoft.com/en-us/powershell/module/whiteboardadmin/, https://learn.microsoft.com/en-us/microsoft-365/whiteboard/manage-data-organizations)

## 11. Planner (formerly "Tasks by Planner and To Do") and To Do

- [ ] The Planner app replaced "Tasks by Planner and To Do" (renamed April 2024). Add it via **View more apps** > search Planner > **Add**, then right-click > **Pin**, or **Open in new window**.
  Source: https://support.microsoft.com/en-us/planner/teams/getting-started-with-planner-in-teams
- [ ] **My Day**:
  - automatically shows tasks due today from My Tasks (Private tasks, Assigned to me, Flagged emails) and from personal plans
  - add tasks manually (due date, priority, source; default source Private tasks)
  - reorder to prioritize
  - clears every night, and unfinished items return to their source plan
  Source: https://support.microsoft.com/en-us/planner/teams/plan-your-day-with-my-day
- [ ] **My Tasks** views:
  - **Private tasks**: quick capture, then move into a plan via **More actions**
  - **Assigned to me**: from Teams meeting notes, basic and premium plans, Loop components, shared To Do lists
  - **Flagged emails**: from Outlook, with a link to the email
  - **All**: aggregate view with filter and sort
  Source: https://support.microsoft.com/en-us/planner/teams/getting-started-with-planner-in-teams
- [ ] **My Plans** shows To Do lists, basic and premium plans, Loop plans and meeting-notes plans. Filters: **Recent**, **Shared**, **Personal**, **Pinned**, **My teams**, **Recommended**, plus **Filter by keyword**.
  Source: same as above
- [ ] **Create a plan / New plan**:
  - blank or template; some templates are premium-only
  - enter a name and an optional Microsoft 365 group (blank creates a personal plan)
  Source: same as above
- [ ] Plan views:
  - per the support page summary: basic plans list Schedule and Charts; premium plans add Grid, Board, Timeline (Gantt with dependencies), People, Goals, Assignments (verify Grid/Board for basic plans live)
  - a task can have up to 11 assignees
  - portfolios (premium) can't be pinned as a tab
  Source: https://support.microsoft.com/en-us/planner/teams/manage-your-team-s-plans-with-planner-in-teams (from search summary; thin)
- [ ] Activity-feed notifications fire when:
  - a task is assigned to you, or an urgent task is assigned to you
  - your task is made urgent or not urgent
  - progress on your task changes
  - you are removed from a task
  Source: https://support.microsoft.com/en-us/planner/teams/getting-started-with-planner-in-teams
- [ ] Planner channel tab: **Add a tab** > Planner > create a new plan or pick a plan shared to the channel or group > **Save**.
  Source: https://support.microsoft.com/en-us/office/add-planner-as-a-tab-in-microsoft-teams-83302f43-f821-47d0-8181-921c36437e22 (from search summary; thin)
- API: two Graph APIs, with a premium-plan gap.
  - Graph Planner API (v1.0) covers plannerPlan, plannerBucket, plannerTask and details, with M365-group containers. **Premium plans and tasks aren't available on the Planner API; only basic plans.**
  - Graph To Do API (v1.0) covers todoTaskList, todoTask, checklistItem and linkedResource, with delta. Private tasks, flagged emails and My Day are To Do-backed.
  - No published API for the My Day ordering, or for the premium Timeline, Goals and People views.
  (https://learn.microsoft.com/en-us/graph/api/resources/planner-overview, https://learn.microsoft.com/en-us/graph/api/resources/todo-overview)

## 12. Approvals

- [ ] **Approvals hub** (personal app) shows all approvals you sent or received, including completed ones. It also aggregates approvals from Power Automate, SharePoint and Dynamics 365. **Sent** lists your requests.
  Source: https://support.microsoft.com/en-us/teams/shifts/what-is-approvals
- [ ] **New approval request** fields:
  - name
  - approvers
  - approval order
  - additional info
  - attachment
  Then **Send**.
  Source: https://support.microsoft.com/en-us/office/create-an-approval-6548a338-f837-4e3c-ad02-8214fc165c84
- [ ] Approval from a chat: compose **(…)** / **Actions and apps** > **Approvals**. Only people already in the chat can be approvers. Includes an **All must approve** option. A live **Approvals card** in the chat shows status and who has responded.
  Source: https://support.microsoft.com/en-us/office/create-an-approval-from-a-chat-07aa429c-fb39-44d6-87da-f5e29a210a0f
  Source: https://support.microsoft.com/en-us/teams/shifts/what-is-approvals
- [ ] Templates:
  - preset fields such as discount request or expense report
  - recipients may be locked
  - org-wide or team templates are created by admins and team owners via the hub overflow menu > **Manage Templates**
  - template responses are stored in Microsoft Forms
  Source: https://support.microsoft.com/en-us/teams/shifts/what-is-approvals
  Source: https://learn.microsoft.com/en-us/microsoftteams/approval-admin
- [ ] E-sign requests:
  - **New approval request** > **Adobe Sign** / DocuSign (classic view: **E-sign**)
  - sign in to the provider
  - **Add attachment** (from provider or computer)
  - per-recipient role **Signer** / **Approver**
  - **Must complete in order**
  - **Prepare** adds signature fields, otherwise **Send**
  - Adobe Sign requests can't be edited after sending
  - not available in GCC
  Source: https://support.microsoft.com/en-us/office/create-and-manage-e-sign-requests-e94cd617-b48e-433c-94c3-7f944a3a8579
- [ ] Storage: basic approvals live in the default Microsoft Dataverse environment (provisioned on first use). A Power Automate license is required, and a Forms license is needed to create templates.
  Source: https://learn.microsoft.com/en-us/microsoftteams/approval-admin
- API: Graph `approvalItem` (create, list, get, cancel, list requests, list/create responses) is **beta only**. There is also Power Automate/Dataverse for workflow approvals. No published API for templates or e-sign.
  (https://learn.microsoft.com/en-us/graph/api/resources/approvalitem?view=graph-rest-beta)

## 13. Shifts

- [ ] Shifts is in the app bar (or **View more apps**). It is auto-pinned for F1/F3 licenses. Desktop and web are optimized for managers; mobile is aimed at workers.
  Source: https://support.microsoft.com/en-us/office/get-started-in-shifts-5f3e30d8-1821-4904-be26-c3cd25a497d6
- [ ] Manager capabilities:
  - schedule: create and share (publish) a schedule; import from Excel; copy a schedule
  - schedule groups: add, update, delete
  - shifts and open shifts: add, update, delete shifts; add open shifts for own team and for other locations; recall shifts
  - settings and requests: schedule settings; approve or deny time-off and shift requests
  - output: time-sheet reports; export to Excel; print the schedule
  Source: same as above
- [ ] Worker capabilities:
  - view own shifts and the team schedule
  - view and request open shifts (own location and **Other locations**)
  - request time off; swap or offer a shift
  - clock in and out of shifts and breaks; edit time-sheet entries
  - set availability and shift reminders
  Source: same as above
- [ ] Schedule views:
  - **Your shifts** (default) and **View** > **Team shifts**
  - date-range picker with arrows
  - **Day** / **Week** / **Month**
  - shift detail offers Swap / Offer
  Source: https://support.microsoft.com/en-us/teams/shifts/view-your-shifts-in-shifts
- [ ] Request flows:
  - open shift: **Request**, then manager approval
  - **Swap**: pick a teammate's shift, add a reason, **Done**; the teammate accepts, then the manager approves
  - **Offer**
  - every step produces activity-feed notifications
  Source: https://support.microsoft.com/en-us/teams/shifts/request-open-shifts-swap-or-offer-shifts-in-shifts
- [ ] Manager **Requests** tab: **In progress** / **Completed** sections, a request detail with note, and **Approve** / **Deny**.
  Source: https://support.microsoft.com/en-us/teams/shifts/manage-shift-requests-and-time-off-in-shifts
- API: Graph Shifts/schedule API (v1.0) covers:
  - schedule, schedulingGroup, shift (draft/shared; 1 min–24 h), openShift
  - swapShiftsChangeRequest, offerShiftRequest, timeOffRequest
  - timeCard with clockIn/clockOut/breaks
  Note: per project memory, OST's current token can't reach Shifts, so the permission needs checking.
  (https://learn.microsoft.com/en-us/graph/api/resources/schedule, https://learn.microsoft.com/en-us/graph/api/resources/shift, https://learn.microsoft.com/en-us/graph/api/resources/openshift, https://learn.microsoft.com/en-us/graph/api/resources/swapshiftschangerequest, https://learn.microsoft.com/en-us/graph/api/resources/timecard)

## 14. Bookings and Virtual Appointments

- [ ] Bookings app: **Apps** > search Microsoft Bookings > **Add**, then pin.
  - Personal Bookings: your own availability and meeting types.
  - Shared Bookings: staff, services, schedules and business hours.
  - Data lives in Exchange shared mailboxes.
  - Online appointments create unique Teams meeting links.
  Source: https://support.microsoft.com/en-us/office/overview-of-the-bookings-app-in-microsoft-teams-7b8569e1-0c8a-444e-b712-d9968b05110b
- [ ] Virtual Appointments / Bookings in Teams:
  - create a Bookings calendar
  - add staff
  - appointment types with emails
  - SMS notifications
  - conduct or join an appointment (lobby admit, end for all)
  - **Queue** view for scheduled and on-demand appointments (Teams Premium)
  - customers join from a browser without Teams
  Source: https://support.microsoft.com/en-us/office/what-are-virtual-appointments-22df0079-e6d9-4225-bc65-22747fb2cb5f (module index; step details thin)
- API: Graph Bookings API (v1.0, `/solutions/bookingBusinesses`, shared bookings only, not personal) covers staff, services, customers, appointments, publish. The `virtualAppointment` resource is deprecated beta; use the join-link function instead. No published API for personal Bookings pages or the Premium queue.
  (https://learn.microsoft.com/en-us/graph/api/resources/booking-api-overview, https://learn.microsoft.com/en-us/graph/api/resources/virtualappointment?view=graph-rest-beta)

## 15. Forms and Polls

- [ ] Chat or channel poll: **Actions and apps** > **Polls** (or **Find more apps**). Creating it:
  - question plus at least 2 options (suggested answers offered; **Options** adds more)
  - **Multiple selections**
  - **Record names of respondents**
  - **Share aggregated results with respondents**
  - **Preview** / **Edit** / **Send**
  Source: https://support.microsoft.com/en-us/teams/apps-service/create-a-poll-in-microsoft-teams
- [ ] Responding and results:
  - voters use **Submit Vote** on the card, and the summary updates live
  - the creator's **More** opens the Forms Responses Overview: active state, count, average time, per-answer counts, **More details** with names
  - **Open results in Excel**, **Check individual results**, delete, print, share
  - **Settings** (who can respond, notifications)
  Source: same as above
- [ ] Meeting Polls tab (organizer or presenter): **Calendar** > meeting > **Chat with participants** > **Add a tab** > **Polls** > **Save** > **Create New Poll**. Poll types:
  - **Multiple Choice Poll** (up to 12 options)
  - **Multiple Choice Quiz**
  - **Word Cloud Poll**
  - **Rating Poll** (scale up to 5, stars or numbers)
  - **Ranking Poll** (first to fifth)
  Settings: Shuffle Options, record names, share results. Launch it before, during or after the meeting; it pops up on screen and in chat. Attendees can create ad-hoc polls.
  Source: https://support.microsoft.com/en-us/forms/poll-attendees-during-a-teams-meeting
  Source: https://support.microsoft.com/en-us/office/get-help-with-the-polls-app-for-microsoft-teams-87d92d26-a638-40bf-ae2f-b03547787698
- [ ] Forms channel tab: **Add a tab** > **Forms**, then either:
  - **Create a shared form that your team can edit**
  - **Add an existing form** with mode **Collect responses** / **Show results** / **Collaborate**
  The tab title is prefixed **Fill |**, **Results |** or **Edit |**. **Post to the channel about this tab** is checked by default. "Allow respondents to edit their responses" is unavailable for Teams-created forms.
  Source: https://support.microsoft.com/en-us/forms/work-with-colleagues-to-create-edit-and-review-forms-in-microsoft-teams
- API: none published for Microsoft Forms or Polls. The Graph reference has no Forms resource (the forms-overview URL returns 404). Polls are Adaptive Cards posted by the Polls app (a bot), so a native client can render the card but can't create or vote on polls through a documented API. Workarounds: results-to-Excel via the Graph Excel API, or open the Forms web URL.
  (https://learn.microsoft.com/en-us/graph/api/resources/excel)

## 16. Lists

- [ ] Lists tab: **Add a tab** > **Lists** > **Save** > **Create a list**. Creation options:
  - **Blank list**
  - **Templates** (preview, then **Use template**; name, description, color, icon)
  - **From existing list**
  - CSV or Excel import
  Lists is preinstalled in the tab gallery. Guests can't create lists. Mobile can view and edit but not create.
  Source: https://support.microsoft.com/en-us/teams/platform/get-started-with-lists-in-teams
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-lists-app
- [ ] **Add an existing list**: lists from the same team, or paste a SharePoint list URL ("standard" lists only; personal lists unsupported). Adding a list doesn't change its permissions.
  Source: https://support.microsoft.com/en-us/teams/platform/get-started-with-lists-in-teams
- [ ] Item actions:
  - **New Item**
  - select > **Edit** (card form)
  - **Quick Edit** grid for bulk cell edits (no multi-item attachments)
  - **Delete** (Shift or Ctrl multi-select)
  - per-item **Conversation** pane
  Source: https://support.microsoft.com/en-us/teams/platform/add-edit-or-delete-items-in-lists
- API: Graph SharePoint list API (v1.0) covers list, columns and contentTypes, listItem CRUD with fields, and delta. List views, formatting, rules and item conversations have no documented Graph equivalent.
  (https://learn.microsoft.com/en-us/graph/api/resources/list, https://learn.microsoft.com/en-us/graph/api/listitem-list)

## 17. Viva apps

- [ ] **Viva Connections** (rebranded "SharePoint app in Teams" in Learn docs):
  - announcements
  - spotlight
  - **Dashboard** of role-targeted cards: **Customize** > add a Quick Links card, hide/show, reorder; **Show more**
  - **Resources** links (up to 48)
  - news reader **News** tab: like, bookmark, **Saved for later**, **Summarize top news** with a Copilot license
  - scoped search
  - Viva app switcher
  Source: https://support.microsoft.com/en-us/viva/connections/viva-connections-on-your-desktop
  Source: https://learn.microsoft.com/en-us/viva/connections/viva-connections-overview
- API: no client API for the dashboard. Extensibility is SPFx Adaptive Card Extensions (web, server-rendered into the host). News comes from SharePoint pages.
  (https://learn.microsoft.com/en-us/sharepoint/dev/spfx/viva/overview-viva-connections)
- [ ] **Viva Engage**:
  - **Apps** > Viva Engage > **Add**, then pin
  - storylines (GA) and communities (preview) in Teams
  - not in Teams: assign leaders/delegates, campaigns/topics, create communities
  Source: https://support.microsoft.com/en-us/topic/get-started-with-viva-engage-729f9fce-3aa6-4478-888c-a1543918c284
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-viva-experiences
- API: the Graph Viva Engage API (native-mode networks) manages communities (`/employeeExperience/communities`) and roles, with membership via M365 groups. No Graph API for posts, feeds or storylines was found in this research. The legacy Yammer REST docs URLs checked returned 404 (thin).
  (https://learn.microsoft.com/en-us/graph/api/resources/engagement-api-overview, https://learn.microsoft.com/en-us/graph/api/resources/community)
- [ ] **Viva Insights**:
  - **Wellbeing** tab: protect focus time, quiet hours, meditation, reflect
  - Productivity: meeting effectiveness, tasks
  - **Teamwork** tab: network, praise
  - insights are private to the user
  - needs Exchange Online and Teams; some features premium
  - auto-installed when the admin enables it
  Source: https://support.microsoft.com/en-us/viva/insights/viva-insights-app-in-teams-and-on-the-web
- API: none published for personal Insights experiences (no Graph resource found).
- [ ] **Viva Learning**: a learning app plus a dashboard card in Connections.
  Source: https://learn.microsoft.com/en-us/viva/connections/available-dashboard-cards (from search summary; thin)
- API: Graph `learningProvider` and `learningCourseActivity` (assignments and self-initiated; list a user's course activities). This is enough to list a user's assigned and recommended courses natively. Course playback is the provider's web content.
  (https://learn.microsoft.com/en-us/graph/api/resources/learningprovider, https://learn.microsoft.com/en-us/graph/api/resources/learningcourseactivity)
- [ ] Other Viva apps listed by Microsoft: **Viva Amplify** (campaigns), **Viva Pulse** (feedback surveys), **Viva Glint**, **Viva Goals**. No user-facing details were gathered (thin).
  Source: https://learn.microsoft.com/en-us/viva/microsoft-viva-overview
- API: none found in this research for Amplify, Pulse, Glint or Goals.

## 18. Video clips and Clipchamp

- [ ] **Actions and apps** > **Record a video clip** in any chat or channel:
  - camera: **Start recording**, pause/resume, **Trim** sliders > **Confirm trim**, **Continue**, back arrow to re-record, **Send**
  - **Screen**: **Start screen recording** > choose screen or window > **Share**; max 1 minute, auto-stops
  - audio-only clip via microphone
  - clips play inline in the conversation
  Source: https://support.microsoft.com/en-us/office/record-a-video-or-audio-clip-in-microsoft-teams-0c57dae5-2974-4214-9c46-7a2136386f1c
- [ ] Clipchamp:
  - enterprise video hub (record, edit, playlists, includes Teams meeting recordings)
  - videos are ordinary SharePoint/OneDrive files
  - pasted video links unfurl into an inline player in chat
  - meeting recordings: open in OneDrive > **Open** > **Edit in Clipchamp**
  Source: https://learn.microsoft.com/en-us/clipchamp/
- API: clips and videos are driveItems (Graph upload and stream download), so a native client can record locally, upload and post as an attachment. The Clipchamp editor has no published API.
  (https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession)

## 19. Help app

- [ ] **Settings and more** > **Help**, containing:
  - **Get help** / Topics: short articles
  - **Video training** / Training: short videos
  - **What's new**: newest first, tabs per platform
  - **Give feedback**
  Source: https://support.microsoft.com/en-us/office/use-a-screen-reader-with-the-microsoft-teams-help-section-and-to-learn-what-s-new-in-microsoft-teams-1fcd3d93-24e9-45f8-857e-8485b420723d (from search summary; thin)
  Source: https://learn.microsoft.com/en-us/microsoftteams/get-help-in-microsoft-teams
- API: none published. Content is support.microsoft.com web pages; link out.

## 20. Apps store: browse, add, pin, request

- [ ] **Apps** (left rail) store:
  - search plus categories
  - app detail page: overview, reviews, details, and where it appears (capabilities: Personal app, Tab, Bot, Messaging extension, Meeting)
  - **Add** button
  - **Filter** > Availability **Ready to add** / **Requires approval**, plus **Request** for blocked apps (admin reviews; you're notified when approved)
  Source: https://support.microsoft.com/en-us/teams/apps-service/add-an-app-to-microsoft-teams
  Source: https://support.microsoft.com/en-us/office/request-apps-that-require-approval-by-your-org-924e3a9e-33f0-44c2-9e81-e875214c05ae
  Source: https://learn.microsoft.com/en-us/microsoftteams/user-requests-approve-apps
- [ ] Add targets:
  - personal app
  - chat or channel tab: **Add a tab** > app > **Add** > configure > **Post about this tab** > **Save**
  - meeting: before via the invite **Add a tab**; during via the **Apps** meeting control
  - messaging area: **Actions and apps**
  Team owners may restrict who adds apps, and some apps are owner-only.
  Source: https://support.microsoft.com/en-us/teams/apps-service/add-an-app-to-microsoft-teams
- [ ] Left rail:
  - **View more apps** flyout
  - right-click > **Pin** / **Unpin**
  - drag to reorder
  - **Open in new window** (pop-out)
  Source: https://support.microsoft.com/en-us/office/pin-an-app-for-easy-access-in-microsoft-teams-3045fd44-6604-4ba7-8ecc-1c0d525e89ec
  Source: https://support.microsoft.com/en-us/office/get-started-with-the-workflows-app-in-microsoft-teams-b7023604-c62a-44d3-a097-fddb68e41ff3
- [ ] Compose-box apps: **Actions and apps** > suggested apps / **Search for apps** / **Get more apps**. Once added, the app icon appears beside the formatting options. Right-click > **Pin** pins it to the compose bar.
  Source: https://support.microsoft.com/en-us/office/insert-app-content-in-microsoft-teams-messages-32bfc3a5-3b07-4a4d-a884-52de852ee8ef
- [ ] Private channels: apps are per channel (not inherited from the team). The first user may be asked to **add the app to this channel**. Manage via channel **More options** > **Manage channel** > **Apps** tab (add, remove, view).
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-apps-private-channels-microsoft-teams
- [ ] Admin governance (affects store visibility):
  - app-centric management (auto-migrated April 2025)
  - per-user or per-group availability
  - guests can't access assigned apps
  - customized store branding
  Source: https://learn.microsoft.com/en-us/microsoftteams/manage-apps
- API: Graph Teams app APIs (v1.0):
  - catalog: `GET /appCatalogs/teamsApps` (with `appDefinitions`: name, description, version, bot); a teamsApp can also be enabled in a specific channel
  - installs: install, list or uninstall in a team (`/teams/{id}/installedApps`), a chat (`/chats/{id}/installedApps`) or personal scope (`/users/{id}/teamwork/installedApps`)
  - permissions: TeamsAppInstallation.* delegated permissions
  - gaps: store reviews, categories, ranking and the "Request" flow have no published API
  (https://learn.microsoft.com/en-us/graph/api/resources/teamsapp, https://learn.microsoft.com/en-us/graph/api/resources/teamsappinstallation, https://learn.microsoft.com/en-us/graph/api/userteamwork-list-installedapps)

## 21. Tabs (channel, chat, meeting, personal) and configuration pages

- [ ] **Add a tab** (+) in a channel, group chat, 1:1 chat or meeting > pick an app > **Add** > configuration page > **Save**. **Post to the channel about this tab** is checked by default. **Posts** and **Shared/Files** are fixed default tabs that can't be removed or moved.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/what-are-tabs
- [ ] Tab context menu (right-click or dropdown arrow):
  - **Rename**
  - **Remove**: in chats anyone can remove; in channels per team-owner settings
  - **Copy link to tab**
  - Settings / reconfigure
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
  Source: https://support.microsoft.com/en-us/office/pin-an-app-for-easy-access-in-microsoft-teams-3045fd44-6604-4ba7-8ecc-1c0d525e89ec
- [ ] **Show tab conversation** opens a side thread tied to the tab's channel post.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/use-a-tab-in-a-channel-or-chat-in-microsoft-teams
- [ ] Tab types:
  - static tabs: personal; also pinnable in chat, channel and meeting without config; one tab per app in chats, channels and meetings
  - configurable tabs: channel, group chat, meeting
  - personal apps (static tabs plus personal bot) sit in the left rail
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/what-are-tabs
- [ ] Configuration page: the app's web page calls TeamsJS `pages.config.setValidityState(true)`, which enables **Save**. `registerOnSaveHandler` then sets `contentUrl`, `websiteUrl`, `entityId` and `suggestedDisplayName`.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/how-to/create-tab-pages/configuration-page
- API: listing and pinning tabs via Graph `teamsTab` (list/add/update/remove for channels and chats; `configuration.contentUrl`, `webUrl`).
  - Rendering any third-party tab requires hosting its web page in an iframe/webview and implementing the TeamsJS host protocol. The host side of TeamsJS is not documented for third-party hosts, so for a strictly native client the practical choice is "Open in browser" using `websiteUrl`.
  - Microsoft first-party tabs (Planner, Lists, OneNote, Forms, Loop, Whiteboard, SharePoint) need the per-app APIs in the other sections.
  (https://learn.microsoft.com/en-us/graph/api/resources/teamstab, https://learn.microsoft.com/en-us/graph/api/channel-list-tabs, https://learn.microsoft.com/en-us/graph/api/chat-list-tabs, https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/how-to/using-teams-client-library)

## 22. Message extensions

- [ ] Invocation points:
  - the compose box (**Actions and apps**, or a pinned icon)
  - the command box
  - a message's **More options** > **More actions** (action commands only)
  Message extensions can't be @mentioned and aren't supported in group chats with external users.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/what-are-messaging-extensions
- [ ] Search commands: query box, then a result list of cards; the chosen card is inserted into the compose box. They can't be triggered from a message.
  Source: same as above
- [ ] Action commands: a modal dialog (web page or Adaptive Card) collects input; the result is inserted into the compose box or posted directly. Multi-step dialogs are possible. Invoking from a message sends the whole message to the app.
  Source: same as above
- [ ] Link unfurling: pasting a URL from a registered domain into compose produces a rich card preview.
  - results are cached for 30 minutes
  - Adaptive Cards ≤ 1.3
  - mobile only unfurls unauthenticated links
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/how-to/link-unfurling
- API: none published for a third-party *client*. The app side is documented (Bot Framework `composeExtension/*` invokes from the Teams service, or API-based extensions via OpenAPI). The client-to-Teams-service call that triggers those invokes isn't documented. A native client can render the resulting cards once posted (they arrive as Graph chatMessage attachments).
  (https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/what-are-messaging-extensions, https://learn.microsoft.com/en-us/graph/api/resources/chatmessageattachment)

## 23. Bots / chatting with apps

- [ ] Add a bot from **Apps** or **Actions and apps**. Chat with it 1:1 or by typing **@AppName** in a group chat or channel. The command list appears as you start typing to the app.
  Source: https://support.microsoft.com/en-us/office/chat-with-a-bot-in-microsoft-teams-9c7bab5e-b1a2-4e35-801a-80d076e26f3f
- [ ] Proactive or RSC bots read conversations without an @mention. Whoever adds one (team owner) must consent to its permissions.
  Source: same as above
- [ ] Bots post text, Adaptive Cards and other card types (Hero, Thumbnail, List, Receipt, Sign-in, Connector, carousels) and can open dialogs (task modules).
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/what-are-cards
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/what-are-task-modules
- API, partly published:
  - Bot messages are normal chat messages in Graph: send to the bot chat via `POST /chats/{id}/messages`, read card attachments.
  - Card button invokes (`Action.Submit` / `Action.Execute` / `task/fetch`) are routed by the Teams client through the Teams service to the bot. That client path is undocumented for third-party clients, so interactive bot cards can't be submitted natively through a documented API.
  (https://learn.microsoft.com/en-us/microsoftteams/platform/bots/what-are-bots, https://learn.microsoft.com/en-us/graph/api/resources/chatmessageattachment)

## 24. Connectors, webhooks and the Workflows app

- [ ] Office 365 Connectors, including connector-based Incoming Webhooks, **retired May 2026**. Replacement: Workflows "When a Teams webhook request is received":
  - Adaptive Card or MessageCard payloads (MessageCard buttons not interactive)
  - 28 KB message limit
  - about 4 requests/s throttle
  - works in private channels
  - flows are owned by users and can be orphaned
  Outgoing Webhooks are per team, triggered by @mention, with a 10 s reply window.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/what-are-webhooks-and-connectors
- [ ] Workflows app (public preview), added via **View more apps**. Home page:
  - template carousel, **All templates**, search
  - **Build from scratch** (trigger plus action)
  - **Your workflows** (5 most recent)
  - **See all**: across Teams, SharePoint, Power Automate and Copilot; toggle **Workflows** / **AI workflows**
  - per workflow **More actions**: **Edit**, **Turn on/off**, **Details** (add **Owners**), **Delete**
  Source: https://support.microsoft.com/en-us/office/get-started-with-the-workflows-app-in-microsoft-teams-b7023604-c62a-44d3-a097-fddb68e41ff3
- [ ] Workflow entry points:
  - chat or channel name **More options** > **Workflows** / **Set workflows**
  - message **More options** > recent actions / **More actions** > **+ Create new action** ("Workflow added successfully!")
  - compose **Actions and apps** > **Workflows** (run or add)
  - **Workflow builder**: AI describe-and-create
  - **+ Create new** opens Power Automate
  - **Manage workflows** links
  - channel connectors now live under **Manage channel**
  Source: https://support.microsoft.com/en-us/office/add-or-run-a-workflow-from-a-message-in-microsoft-teams-921ce26d-265e-401e-b062-06dd3ae2f0c5
  Source: https://support.microsoft.com/en-us/office/add-or-run-a-workflow-in-chats-chat-messages-channels-and-channel-posts-in-microsoft-teams-242eb8f2-f328-45be-b81f-9817b51a5f0e
- API:
  - Power Automate (Dataverse flows). The Teams "for a selected message" trigger is fired by the Teams client, and that client contract is undocumented.
  - Webhook-triggered flows are plain HTTPS POST (documented).
  - For managing flows: Power Automate Web API / Dataverse (not fetched; thin).
  (https://learn.microsoft.com/en-us/power-automate/teams/overview, https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)

## 25. App permissions and consent

- [ ] Permission kinds and who grants them:
  - basic capabilities are granted when an app is added
  - delegated Graph permissions: user or admin consent per Entra configuration
  - application permissions: admin only
  - RSC (resource-specific consent): team owners or chat members consent at install for that team, chat or user; low-risk ones by any user
  - max 16 RSC permissions per app; delegated RSC needs manifest ≥ 1.12
  Source: https://learn.microsoft.com/en-us/microsoftteams/app-permissions
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/rsc/resource-specific-consent
- [ ] User-visible prompts:
  - app detail page lists permissions and where the app appears
  - consent prompt on adding RSC or proactive bots
  - first-party apps such as Approvals declare e.g. "Receive messages and data", "Send you messages and notifications", "Render personal apps and dialogs without a Teams-provided header"
  Source: https://learn.microsoft.com/en-us/microsoftteams/approval-admin
  Source: https://support.microsoft.com/en-us/office/chat-with-a-bot-in-microsoft-teams-9c7bab5e-b1a2-4e35-801a-80d076e26f3f
- API: Graph `teamsAppDefinition` (manifest metadata; RSC declared in `authorization.permissions.resourceSpecific`), `installedApps` installs with consent (`TeamsAppInstallation.ReadWriteAndConsent*` permissions), and permissionGrants list APIs.
  (https://learn.microsoft.com/en-us/graph/api/resources/teamsappdefinition, https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/rsc/resource-specific-consent)

## 26. Adaptive Cards and dialogs (rendering in messages)

- [ ] Card types Teams renders: Adaptive Card, Hero, Thumbnail, List, Receipt, Sign-in, Connector (MessageCard), carousels and lists of cards, and the Adaptive Card overflow menu. A People Picker input is available in Adaptive Cards.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/what-are-cards
- [ ] Actions:
  - **Action.Execute** (Universal Actions, sent to the bot)
  - **Action.Submit** (legacy)
  - **Action.OpenUrl**
  - **Action.ShowCard** (nested)
  - **Action.ToggleVisibility**
  - legacy messageBack, imBack, invoke, signin
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-actions
- [ ] Universal Actions:
  - user-specific views (different buttons per user)
  - sequential workflows (Execute returns a new card)
  - auto-refresh ("up to date views")
  - Action.Execute unsupported for message-extension result cards
  - link-unfurl cards need Action.Submit
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/universal-actions-for-adaptive-cards/overview
- [ ] Dialogs (task modules): a modal with app icon, short name, title and close. Body is either a web page (iframe) or an Adaptive Card; the last root action renders as the primary button. Opened from tabs, bot cards or deep links.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/what-are-task-modules
- [ ] Workflows and Approvals/Polls cards are Adaptive Cards in messages.
  Source: https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
- API:
  - Rendering: the Adaptive Card JSON schema is public (Adaptive Cards documentation hub), and card JSON arrives in Graph `chatMessageAttachment.content`, so native rendering is fully possible.
  - Action.OpenUrl and ShowCard/ToggleVisibility work client-side.
  - Not published for third-party clients: Action.Submit/Execute, refresh and dialog `task/fetch` invocation, which go through the Teams service.
  (https://learn.microsoft.com/en-us/graph/api/resources/chatmessageattachment, https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-format)

---

## Summary: embedded experience vs published API

| Experience | Usable published API? | Notes |
|---|---|---|
| OneDrive app / files / share / versions | Yes (Graph drive v1.0; beta for review/blocksDownload links) | No OneDrive for Business recycle-bin restore; no "browse by" endpoints |
| Office file view | Partial (Graph convert to PDF/JPG ≤ 2 MB; preview URL is web) | |
| Office file edit in-app / co-authoring | None published | WOPI is partner-only; desktop launch via Office URI schemes |
| Loop components / Channel Pages / Loop workspaces | None published | .loop is a driveItem with an undocumented format; odsp-client only for own containers |
| Notes tab (OneNote) | Yes (Graph OneNote, delegated only) | HTML subset, PATCH commands, lossy |
| Whiteboard | None published | .whiteboard is a driveItem; admin PowerShell only |
| Planner / To Do | Yes (basic plans, To Do) | Premium plans not in Graph |
| Approvals | Beta only (approvalItem) | Templates and e-sign not covered |
| Shifts | Yes (Graph schedule) | Needs Schedule permissions |
| Bookings | Yes for shared bookings | Personal bookings and queue not covered |
| Forms / Polls | None published | Excel workaround |
| Lists | Yes (Graph list/listItem) | Views/rules not covered |
| Viva Connections | None (SPFx ACE web only) | |
| Viva Engage | Communities management only | No posts/feed API found |
| Viva Insights / Amplify / Pulse / Glint / Goals | None found | |
| Viva Learning | Yes (learningCourseActivity) | Content is provider web |
| Clipchamp / clips | Files via Graph; editor none | |
| Help | None | Link out |
| App store / install / tabs list | Yes (Graph appCatalogs, installedApps, teamsTab) | Rendering third-party tabs needs a web host |
| Message extensions / bot card actions / dialogs | None published for clients | Rendering cards OK; submitting not |
| Workflows | Webhook POST documented; message-trigger client path not | |
