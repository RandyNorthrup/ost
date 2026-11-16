# A chat's Notes, Recap and Storyline tabs — Teams behaviour (spec)

Measured in Teams on the web (teams.cloud.microsoft, the same React client
as Teams desktop, build 26101515220) as ost-test1 on 2026-11-16, inside
OST's own web profile on linuxlt, through its DevTools port (CSS px, the
page 1212 x 700 at devicePixelRatio 1; the tab area is 864 x 555 under the
61 px header). Chats used: OST group test, OST Test 2 (1:1, read only),
your own notes chat (48:notes) and the "Meeting with OST Test 1" chats.
Module names are from that build's chat-app bundle and worker.
OST: `api::chat_notes`, `ChatNotesTab.qml`, `RecapTab.qml`,
Conversation.qml's Storyline loader, `--chat-tab-test`.

## Which tabs (tab ids `com.microsoft.chattabs.*`)
- Group chat: Chat, Shared, Notes (`chatnotes`), Recap (`recap`), "+".
- 1:1 chat: Chat, Shared, Notes, Recap, Storyline (`storyline`), "+".
- Your notes chat (48:notes): Chat, Shared, Notes, Storyline; no Recap,
  no "+".
- Meeting chat: Chat, Shared, Recap, … (add-a-tab.md); no Notes.

## Notes (FluidThread; chat-app 590499, the worker's `thread_file_reference`)
**What it is.** One Loop page per chat, `loop_loopThread.loop`, in a
SharePoint Embedded container (`/contentstorage/CSP_{container}/Document
Library/{thread with : @ . as _}/`). The chat service keeps it:
- `GET {chatsvc}/v1/threads/{thread}?view=msnp24Equivalent` lists it under
  the top-level `fileReferences` (not `properties`):
  `{"{id}": {"createdAt", "creator": "8:orgid:…", "driveId": "b!…",
  "fileReferenceId": "{item id}", "id", "provisioningStatus": "completed",
  "subType": "loopthread", "type": "loop", "uri": "https://…/loop_loopThread.loop?nav={base64}"}}`.
- Opening the tab when there is none makes it:
  `POST {chatsvc}/v1/threads/{encodeURIComponent(thread)}/files` with
  `{"type":"loop","subType":"loopThread"}`; the reply is the new
  reference. Create new (after deletion) adds
  `?forceCreateFile=true&forceCreateReason=ClientFileNotFound`.
  (Request read from the worker's code; the file was made, with
  `createdAt` the moment the tab was opened, when Notes was first opened in
  OST group test — the request itself runs in the worker, which the
  DevTools network view doesn't show.)
- The chat service then posts **ThreadActivity/FileAdd**:
  `<fileadd><eventtime/><initiator/><target><id/><uri/><type>loop</type><subtype>loopthread</subtype><creator/><createdAt/></target></fileadd>`,
  shown as the row "Notes have been created in this chat." (the
  DocumentEdit 20 icon; "Notes" a link in the row's colour that opens the
  tab).
- Which reference: those with type loop / subType loopthread that aren't
  DELETED, the first by id (`FF`). Status order: FAILED 0, INPROGRESS 1,
  FILECREATEDWITHINITIATORPERMISSION 2, COMPLETED 3, DELETED 4. With
  FILECREATEDWITHINITIATORPERMISSION only the creator gets the address;
  others wait. Updates come through the thread's update events.

**What Teams draws** (the Loop host's shared header with Teams' overrides,
`oF`; in Teams' own page):
- a 48-tall row, padding 0 16 (`max-height: 4.8rem`, padding 1.6rem 1rem):
  "Notes" (`fluid_thread_tab_header_text`, 14/20 semibold #242424) at
  (28, 14); a Presence toolbar (collaborators' pictures, empty when alone);
  the 20 px LockClosed (regular, NeutralForeground2 #424242) 16 from the
  right, tooltip below "Only accessible to members of this chat"
  (`fluid_thread_tab_lock_tooltip`); title not clickable, no Copy, no
  Permissions, no Loop control;
- a 1 px #E0E0E0 divider at 48;
- **state pages** (`Ir`, `data-testid=fluid-thread-state-page`), centred,
  min-height 260: the picture 192 x 192
  (`{statics}/v2/workspace-{l|d}-standard.svg`; errors
  `warning-{l|d}-standard.svg`; d for dark and high contrast), the message
  h4 (16/22 bold, centred, margin 0 20), details (14/20) and a primary
  button:
  - loading: "Give us a moment while we get things ready for you...";
  - deleted (404 "File confirmed to be deleted from SPE", with
    `enableFluidThreadFileRecreation`): "Your notes have been deleted." and
    **Create new**; without the flag "These notes have been deleted" /
    "This is due to your org's policies. You'll be able to add new notes
    soon. Check back later.";
  - 403 / 400: "Your notes are temporarily not available."; other errors
    the same with **Retry**.

**What Teams embeds.** The page itself is Loop's page container, not
Teams' code: a `srcdoc` iframe (`<div id="componentDiv">`, 864 x 506 under
the divider) into which Teams loads
`res.cdn.office.net/fluid/prod/odsp-driver/hashed/index.*.js`,
`…/loop-page-container/hashed/runtime.*.js` and `loopPageContainer.*.js`,
then hosts it as a Fluid container (`window.loopPageContainer.fluidExport`,
`window.FluidOdspDriver.getDocumentServiceFactory({tokenProvider,…})`,
Teams' host chunk 205902) with Teams' own SharePoint and push-channel
tokens. It talks to `{tenant}.sharepoint.com/_api/v2.1/drives/{drive}/items/{item}/opStream`
(snapshots, joinSession). Inside the frame: the canvas ("Just start
typing...", padding 12 40) and the insert row (Table, Bulleted list,
Checklist, Task list, Voting table, More: 32 tall, radius 6, a #D1D1D1
line, padding 5 12, 14/20, 12 apart, 40 in, 16 above the bottom).
- The file can't be opened outside Teams: the Loop web app
  (loop.cloud.microsoft/p/…, which the file's `:fl:` link redirects to)
  gets **403 accessDenied** on the container, and the file's address goes
  to SharePoint's "You can't access this item". Only Teams' apps may open
  this container, so showing the page needs OST to host Loop's page
  container itself.

## Recap (chattabs.recap; drawn by Teams, no frame)
**A chat without a recap** (group, 1:1): no requests besides the picture.
- #F5F5F5, padding 0 12 12; a 600-wide box (padding 24) centred: the
  picture 256 x 256
  (`evergreen-assets/illustrations/v2/meeting-notes-l-standard.svg`); "No
  recap in this chat" (16/22.86 bold) 24 under it; "Turn on transcription
  during a call to get a recap with notes and follow-up tasks." (14/20) 10
  under that.

**A meeting chat** (intelligent recap; seen in a "Meeting with OST Test 1"
chat: one Meet now call, no recording, no transcript):
- `intelligent-recap-header`: 48 tall, #F5F5F5, padding 8 12; at the right
  **Open Copilot** (`recap-copilot-button`, 32 x 32) and **More options**
  (32 x 30, 20 from the right): Go to Meeting Recaps, Delete recap content
  (menu 184 wide, 32 px items).
  - Copilot opens Microsoft 365 Copilot's page in a pane beside the chat
    (an iframe, `m365copilotapp.svc.cloud.microsoft/chat?…&hostApp=hub`);
  - Go to Meeting Recaps did nothing visible on the web.
- `meeting-recap-main-panel`: #F5F5F5, padding 0 12 12:
  - **Shared files** card (white, radius 8, padding 12 0, 8 above the
    next): "Shared files" (h2, 14/20 semibold, 16 in); the items 2 under it
    (padding 2 0 2 15): **Attendance** (399 x 32, white, a #F0F0F0 line,
    radius 4, padding 6 12 6 10, the 20 px attendance-report icon, the name
    12/20 at 45), which opens the Attendance tab;
  - the pages card (white, radius 8) to the bottom: pills (`role=tablist`,
    12 in, 12 down) **AI summary** (`AINotes`), **Mentions**,
    **Transcript**: 32 tall, radius 15, padding 5 8, 13/20, 8 apart; the
    chosen one #E8EBFA with a #444791 line and #4F52B2 semibold, the others
    a #D1D1D1 line and #424242; their width holds the semibold name; a
    hairline 56 down; then the pill's page, centred in 600 (padding 24):
    the picture 192, its title (16/22.86 bold) 24 under it, its text
    (14/20) 8 under that:
    - AI summary: meeting-notes; "Get AI-powered meeting summary"; "When
      Intelligent recap is turned on, AI can generate notes and suggest
      tasks to follow up on.";
    - Mentions: `tag-l-standard.svg`; "Know if your name came up"; "Turn
      on transcription, and AI will find mentions of you in the
      transcript.";
    - Transcript: meeting-notes; "No transcript available"; "The
      transcript for this meeting was never created, has expired, or has
      been deleted."
- With the Copilot pane open the header narrows (the tabs collapse to a
  "Recap ▾" dropdown under the title).

## Storyline (chattabs.storyline; Viva Engage, embedded)
- A `hwc-iframe` (cacheable, `name=embedded-page-container`, title
  "Storyline", app `683f3525-d193-4a67-8d91-22093beab1ca`) filling the tab
  (864 x 555), sandbox `allow-storage-access-by-user-activation
  allow-scripts allow-same-origin allow-top-navigation-to-custom-protocols
  allow-forms allow-popups allow-popups-to-escape-sandbox allow-pointer-lock
  allow-modals allow-downloads`, allow `clipboard-write *;
  media-playback-while-not-visible 'none'; local-network-access *;`.
- Address: `https://engage.cloud.microsoft/teams-branded-exp/officeusers/{oid}/storyline?hostappname=TeamsModern&appsessionid={uuid}`,
  `{oid}` the other person's in a 1:1 chat, yours in your notes chat. The
  frame is kept and moved to the next person's storyline.
- It is a TeamsJS app: it sends `getContext`, `appInitialization.success`
  ("2.49.0") and `readyToUnload`. Loaded on its own it shows "There was an
  error loading this page / Try reloading this content. / Reload".
- What it shows (Engage's): the cover, the person's 72 px picture, name,
  Followers / Following / Posts, "Follow storyline" (others) or "What is a
  storyline?" with Add a cover photo (yours), then Storyline / Community /
  All.

## OST status
- [x] The tabs as Teams lists them (your notes chat now has Notes).
- [x] Notes: the thread's notes file read and made as Teams does
  (`POST …/files`), Teams' header and lock, the loading, deleted (Create
  new) and error (Retry) pages; the "Notes have been created in this
  chat." row with its link.
- [ ] Notes' page: needs OST to host Loop's page container (a Fluid
  container with Teams' SharePoint tokens). Until then OST says "OST
  can't show these notes yet." with Open in browser.
- [x] Recap: the empty chat page; the meeting recap's layout, Shared files
  (Attendance opens the Attendance tab), the three pills and their empty
  pages.
- [ ] Recap with content (a recording, transcript, AI notes, mentions):
  not seen, the test meetings have none; Copilot (an embedded page) and
  More options' items (shown off).
- [x] Storyline: Teams' page for the right person in place, in OST's web
  profile.
- [x] Storyline running in OST's TeamsJS host (docs/spec/app-host.md):
  Engage's page initializes, gets its NAA token (client f4060917, scope
  `https://engage.cloud.microsoft/teams-branded-exp/access_as_user`) and
  shows the person's storyline (seen for OST Test 2, 2026-11-16).
  Its context is Teams': entityId `storyline`, the chat's id, meetingId
  base64 of `0#<chat>#0`, teamSiteDomain the tenant's SharePoint host,
  manifestVersion 1.25; it also asks shortcutRelay.getHostShortcuts.
