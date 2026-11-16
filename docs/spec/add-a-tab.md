# Add a tab, and a meeting chat's tabs — Teams desktop behaviour (spec)

Measured on the Windows Teams desktop app on winpc, signed in as ost-test1,
on 2026-11-16, through the WebView2 debugger (CSS px, the window at 1280 x
680, devicePixelRatio 1.5). Requests were captured from the page and its
web worker while adding and removing a website tab in **OST group test**
and in **OST Test Team › General**. Module ids are from build 26276.513's
bundles (454179 tab list, 62752 platform-modal in-context Store, 811630 /
143369 the in-context Store's data, chat-app `Zv` / `ny` the chat tabs).
OST: `api::tab_add`, `api::store_content::{IcKind, ic_collections}`,
`AgentStore.qml` (tab mode), `TabConfigDialog.qml`, `BreakoutTab.qml`,
Conversation.qml's "+".

## The "+" (add-tab-button, module 454179 `$t`)
- After the tabs and "+N": a transparent Fluent button, 32 x 60.3, padding
  5, `role=tab`, aria label and tooltip **"Add a tab"**
  (`add_tab_aria_label`, tooltip below, 2 away).
- The 20 px AddSquare: regular, #424242; hovered (and while its menu is
  open) the filled glyph in brand #5B5FC7.
- It shows in group chats, 1:1 chats, meeting chats and channels.
- **Chats and meeting chats**: it opens the Add a tab picker at once.
- **Channels** (`extraAddTabActions`): a menu first (`add-tab-menu-item-*`),
  1 below the button, 128.7 wide (items 32 tall, a 20 px icon at 6, the
  label at 30, 14/20 #424242):
  1. New page (`addChannelPage`, the Loop glyph);
  2. Existing page (`linkChannelPage`, Link);
  3. New list (`addNewList`, the Lists glyph);
  4. Existing list (`linkExistingList`, the table-link glyph);
  5. Apps (`defaultAddTabAction`, `add_app_label`, Apps) — the picker.

## The picker (in-context Store, Tab capability; `ic-store-content`)
The same dialog as "Add agent" (store.md §3), with Tab's own content:
- **Dialog**: "Add an app", 901.3 x 647.3, radius 8, white, shadow 64.
- **Search**: "Search for apps", 802.7 x 30.7 input at (33.3, 33.3), the
  20 px search icon at 838.
- **Grid** (`in-context-grid`, `InContextStoreGridAppsRenderer`): your apps
  that have a tab here, as 104 x 100 cells (100 x 96 buttons, radius 6; a
  48 px round icon on #FAFAFA 8 down, the name 12/16 #242424, one line at
  70 or two at 62), centred in the 834 px area (margin 2rem 1.6rem 2rem 0).
  - With more than 5 apps it shows 4 and **See all** (a 49.3 px box,
    0.67 px #D1D1D1, radius 4, white, the 16 px grid icon), which shows
    them all (8 a row, the last row centred) and **See less**
    (`inContextStoreAppsMinCount` 7, less 3 off the desktop view).
  - **Which apps**: the conversation's apps with a state there — the
    worker reads `GET {mt}/beta/chats/{thread}/apps/definitionsv2` (also for
    a channel's thread; six pages of 600 with `x-ms-continuation`, each
    app with its `state`: Website and PDF are InstalledAndPermanent there
    though not among your entitlements, Viva Learning, yours only, has
    none) plus, in a channel, the team's apps — in states other than NotInstalled,
    InstalledAndHidden, InstalledAndDeprecated, Featured; Pages
    `5ae80e49-…` filtered out) with a configurable (gallery) or static tab
    whose `scopes` hold the install scope (GroupChat for chats, Team for
    channels) and whose `context`, when it has one, holds the place's
    (`privateChatTab`, `meetingChatTab`, `channelTab`) (module 143369 `V`/`ie`).
  - **Order**: most recently used first (`GET {mt}/beta/users/apps/usage`
    → `appsMru`, `enableAppUsageRecordingWithTimeStamp`; module 143369
    `v8`), the rest in their own order. Using an app moves it first: after
    adding a website tab Website led both grids.
  - Seen for ost-test1. OST group test: OneNote, Whiteboard, Website, PDF,
    Visio, Word, Excel, PowerPoint, Power Apps, Power BI. General:
    OneNote, Whiteboard, Planner, PDF, Website, Visio, Word, Excel,
    PowerPoint, Loop, SharePoint Pages, SharePoint, Forms for Microsoft
    Teams, Power BI, Lists, Power Apps, Workflows.
- **"Add a new app"** (16/16 semibold #424242) on a centred rule, 20 under
  the grid.
- **Collections**: `inContextStoreCollectionIdsOverwrite.Tab` (tenantapps,
  suggestedapps, abctab4, popularapps, abctab1, productivity, abctab2,
  abctab3, microsoft, education), each with the apps that have a tab here
  (not the grid's), shown with at least 6 such apps; cards as Add agent's.
  - OST group test: Popular on Teams, Productivity tools, Idea boosting
    tools, Education.
  - General: Agents we love, Popular on Teams, Productivity tools, Manage
    tickets effectively, Idea boosting tools, Built by Microsoft, Education.
- **Footer** under a 0.67 px rule at 574.7: Manage your apps
  (`in-context-store-manage-apps-btn`, 32 x 31.3) 32 in, then Close (96,
  outline) and Get more apps (118.8, brand) right-aligned 32 in, at 595.3.
- A grid app opens its **tab configuration**; a collection's app opens its
  details (Add, then its configuration).

## Tab configuration (platform-modal app-configuration dialog)
- 600 wide (593.3 tall for Website, 595.3 for PDF), padding 24, radius 8,
  shadow 64.
- **Header** (`platform-app-config-header`) at (24.7, 32.7), 43.2 tall: the
  app's 36 px round icon on #FAFAFA; its name (h2, 14/20 semibold) at 72.7;
  **About** (96 x 31.3, transparent, 14 #4F52B2) at 447.3 and Close
  (`platform-app-configuration-header-close-button`, 32 x 31.3, dismiss 20
  #424242) at 543.3.
- **Footer** (`platform-app-config-footer`) at 526.7: a checked checkbox
  and **"Post to the chat about this tab"** ("…to the channel…" in a
  channel; 14/20, label padding 8 8 8 4), **Back** (96 x 32, outline, back
  to the picker) and **Save** (96 x 32, brand; off: #F0F0F0 with #BDBDBD).
- **Website** (`com.microsoft.teamspace.tab.web`) is drawn by Teams:
  - a message bar (`app-configuration-message-bar`) at 91.9: 550.7 x 32.7,
    #F0F0F0, 0.67 #D1D1D1, radius 4; the filled 14 px info icon, "This site
    will be added as a tab and open in a browser window." (12/16
    semibold), and a close button;
  - **Tab name** (14/20) at 140.6 over a filled field at 160.6 (550.7 x 32,
    #F5F5F5, radius 4, text at 12, brand focus line), "Website" at first,
    with a 20 px validity icon 10.7 from its end: CheckmarkCircle filled in
    #5B5FC7, or ErrorCircle filled in #BC2F32;
  - **URL\*** at 222.6 over its field at 242.6 (no icon while empty); an
    invalid URL puts **"That isn't a valid URL."** (14/20 #D13438) at the
    label row's end and turns Save off. Tried: `https://example`,
    `https://x`, `https://localhost`, `https://example.com/x?y=1` pass;
    `http://…`, `example.com`, `www.example.com`, `HTTPS://example.com`,
    `https://`, a space anywhere, `<` or `%` in the host fail;
  - the hint (12/16, weight 200) at 284.6: "*Make sure you're only linking
    to sites that start with 'https://' and contain trustworthy web
    content. That way, you and your team can stay secure."
- **Other apps** (OneNote, PDF, …): the app's configuration page in an
  iframe at (24.7, 75.9), 550.7 x 452.8 (PDF: the OneDrive file picker);
  the page turns Save on through TeamsJS.

## What Save sends (captured)
Both a chat's and a channel's tabs live in the conversation thread's
properties (`tab::{guid}`), set through the chat service:
1. `PUT {chatsvc}/v1/threads/{thread}/properties?name=tab::{guid}` with
   `{"tab::{guid}": "<tab JSON>"}`. The tab JSON, in this key order:
   `{"id":"tab::{guid}","order":110000,"definitionId":"com.microsoft.teamspace.tab.web","directive":"webpage-tab","type":"tab:","settings":{"url":"https://example.com","websiteUrl":"https://example.com","dateAdded":"2026-11-16T07:55:18.702Z"},"name":"Website"}`.
   The order is the worker's (`last > 100000 ? last + 10000 : 110000`):
   110000 in both (General's Page is 10, Notes 10000).
2. With "Post to … about this tab": `POST
   {chatsvc}/v1/users/ME/conversations/{thread}/messages`, Text **"I added a
   tab at the top of this chat. Check it out!"** ("…of this channel…"),
   `properties.files` holding the tab as a `deeplink` file (as Start
   conversation's post, channel-tabs.md).
3. The same PUT with `"replyChainId":"<the post's id>"` added at the end.
- **Remove** (Want to remove this tab? › Remove), chats and channels alike:
  `PUT …/properties?name=tab::{guid}` with `{"tab::{guid}": null}`.
- The chat then shows the post: "I added a tab at the top of this chat.
  Check it out!" with the tab's card (`deep-link-chiclet-{name}`: #FAFAFA,
  0.67 #F0F0F0, radius 4, padding 7 3 7 11, the 38 px icon, the name 14/20
  semibold at 60.7).

## A chat's own tabs
- They follow the built-in ones; in OST group test the website tab went
  under "+1" (the "+" keeps its 32 px).
- The "+N" menu shows such a tab as `tab-item-with-submenu`: its name, a
  0.67 px divider and a 32 x 28 chevron (`tab-item-chevron`, "Has context
  menu") that opens its menu.
- A website tab's menu in a chat: Copy link to tab, divider, Rename, About
  this tab, divider, Remove — no Move left / Move right (a channel's has
  them). In a channel too there is no "Open in browser" for a website tab.

## A meeting chat's tabs (chat-app `Zv`, `ny`)
- Chat, Shared, Recap, then:
  - **Attendance** (`chattabs.attendancereport`): `hasAttendanceReport`;
  - **Breakout Rooms** (`chattabs.breakoutrooms`): for the meeting's
    organizer, not cancelled, not a room's own chat (`scenario`), not a
    town hall template or broadcast;
  - **Q&A** (`chattabs.qna`, the Viva Engage Q&A app
    `5db56dd0-534d-467b-aeda-d622bee2574a`): a scheduled meeting
    (`isScheduledMeeting`: its `meeting` thread property has an `iCalUid`;
    "Meeting with OST Test 1" chats are Meet now, `iCalUid: null`, and have
    none) with `enableMeetingChatYammerQnATab`;
  - **Meeting Whiteboard** (`chattabs.whiteboard`): every meeting.
- Whatever doesn't fit goes under "+N"; an opened one moves out of it.
- Seen: the six "Meeting with OST Test 1" chats: Chat, Shared, Recap,
  Attendance, "+2" (Breakout Rooms, Meeting Whiteboard). "OST calendar
  test: created from OST": Chat, Shared, Recap, "+4" (Attendance, Breakout
  Rooms, Q&A, Meeting Whiteboard).
- **Breakout Rooms** is native (pre-meeting assignment), 892 x 571 under
  the header, no fill of its own (the window's #EBEBEB), padding 14 0 0 21:
  - "Assign participants" (174 x 31.3, its people icon, 14/600; off and
    #F0F0F0 / #BDBDBD, border #E0E0E0, until there are rooms) at (21, 14);
  - the room actions toolbar ("Room action buttons"), 32 x 32 each, 5 apart,
    20 from the right: Add room and Remove (off until there are rooms),
    Room settings;
  - no rooms: centred right of the padding, the picture 220 x 142.3 at
    138.1; "Create breakout rooms" (24/32 bold) at 312.4; "See your rooms
    and set them up the way you want, all right here." (16/22.86) at
    360.4; Create rooms (`create-breakout-rooms-button-main`, brand, 110.3 x
    31.3) at 415.3; Import from CSV (outline, 132.9 x 31.3) at 462.6;
  - Create rooms opens "Create rooms" (600 x 176.7, 20/28 semibold), "How
    many rooms do you need?" with a number field (2), Cancel and Add rooms.
  - Its requests are the breakout room service's without `?newVersion`
    (services-breakout-rooms `g`: none without a version), on the meeting's
    coordinates `{tenant}/{organizer}/19_meeting_…/0`.
- **Q&A** and **Meeting Whiteboard** embed Microsoft's pages in the tab
  (`hwc-iframe`, the tab's full size):
  - Q&A: `https://web.yammer.com/teamsmeeting/teams-meeting/{base64 of
    {"_type":"TeamsMeeting","id":"<base64 of 0#{thread}#0>"}}?client=teams&qnaAppType=native&meetingTenantId={tenant}&entryPoint=chatTab&appSessionId={uuid}`;
  - Whiteboard (app `95de633a-…`): `https://app.whiteboard.microsoft.com/meeting?embed=1&meetingTitle={title}&tabStartTime={ms}&correlationId={uuid}&culture=en-us&enableReactApp=1&isInitiator=1&isEduUser=0&meetingId={base64 of 0#{thread}#0}&teamsEnvV2=prod&client=TeamsModern&userRole=Member&isEU=false&userId={oid}&userTenantId={tenant}&isNAAEnabled=true`
    (it goes on to the board's own address).

## OST status
- [x] "+" in chats, meeting chats and channels; its look, tooltip and the
  channel's menu (Apps opens the picker).
- [x] The picker: grid (your tab apps, most recently used first, See all /
  See less), Tab collections, search, footer.
- [x] Website's configuration, validation and Save exactly as captured (the
  property, the post, the reply chain); the tab shows for everyone (it is
  the thread's).
- [x] A chat's own tabs from its thread properties, under "+N" with their
  menus; Remove (thread property to null) for chats and channels;
  Rename for chats (the property with the new name).
- [x] Meeting chats: Attendance, Breakout Rooms, Q&A, Meeting Whiteboard
  as Teams lists them; Breakout Rooms native (empty state, Create rooms).
- [ ] Q&A and Meeting Whiteboard load Teams' pages in place, but both need
  a TeamsJS host: Whiteboard stops at "Something went wrong" (its TeamsJS
  "Initialization Failed. No Parent window found."), Q&A's sign-in fails
  (AADSTS700054, it signs in through the host) — TASK-0053.
- [ ] New page, Existing page, New list, Existing list (shown, off).
- [ ] Other apps' configuration pages need a TeamsJS host (TASK-0053): the
  page is embedded, Save stays off.
- [ ] Breakout Rooms with rooms (the room list's layout), Assign
  participants, Room settings and Import from CSV in the tab.
