# Store, in-context Store (Add agent) and Teams' live settings

Measured on winpc on 2026-11-09 against Teams 26276.513. The sources are:

- the dialog's DOM (read-only CDP);
- a startup network capture;
- the worker's IndexedDB caches;
- Teams' bundles: `services-io-store-apps`, and the web worker's `inner_b`, `inner_c` and `inner_services_i` chunks;
- the burnt-in `config-prod`.

## 1. Teams' live settings (ECS)

At start, Teams desktop's settings provider asks:

`GET https://config.teams.microsoft.com/config/v1/MicrosoftTeams/49_1.0.0.0`

The request needs no auth. Its query parameters, in order:

- **Client:**
  - `environment=prod`, `experience=react-web-client`, `buildType=production`, `virtualization=`;
  - `browser=edge`, `browserVersion`, `osPlatform=windows`, `wipChannel=`, `wipRing=`, `osVersion`;
  - `isOcdi=false`, `isPwa=false`.
- **User:** `id` and `aaduserid` (the object id), `tenantId`.
- **Build:** `experienceBuild` (the web build, 26101515220) and `desktopVersion` (26276.513.5241.9675).
- **Licence and region:**
  - `teamsLocale=en-us`;
  - `teamsLicenseCategory` (authz `licenseDetails.experimentationTeamsLicenseCategories`, e.g. TeamsSmb);
  - `mtmaCount=1`;
  - `TeamsMeetingRoomLicenseCategory` (None when empty);
  - `Region` (amer);
  - `TeamsLicenseCategory` (SmbLicense is sent as TeamsSmb).
- **Session:** `sessionId` and `clientId` (per-session ids).
- **Agents:** `agents=TeamsNorthstar,TeamsBuilds,Segmentation,TeamsNorthstarUserOverrides`, then `ECSCanary=1`.

The reply (about 430 KB) holds the agents plus `Headers` (with an `ETag`) and `ConfigIDs`.

- A setting is read from TeamsNorthstarUserOverrides, then TeamsNorthstar (namespace, then key). Teams' burnt-in `config-prod` defaults sit underneath.
- Without the licence filters, the reply lacks whole namespaces, such as `extensibility`.
- OST reads authz `licenseDetails` (`teams_cli::auth::skype`) and keeps it in the config. `teams_cli::api::ecs` makes this request, caches `ecs.json` with its ETag, and serves `setting(ns, key)` and `segment(key)`.

## 2. Store data

### Store content
- **The doc:** `https://res.cdn.office.net/teamsappdata/evergreen-assets/storecontent/{link}.json?ts={floor(now / 7200000)}`.
  - `{link}` is `apps` + `/smb` for SMB users (`/edu` for student or teacher licences) + `/` + ECS `extensibility.storeAppsCollectionsDoc`.
  - The doc is `Enterprise/NewStoreCustomization/storev3` for ost-test1; the burnt-in default is `storev2?v=2`.
  - A query in the doc goes after `.json`.
  - It is cached 480 minutes (`storeContentCollectionsMaxAgeInMinutes`).
- **Collections:** `collectionsList[] {id, order, group, isInFeed, feedOrder, title, subtitle, description, templateType, isHidden, itemsList[{id, title}]}`.
  - A collection whose single item has the collection's own id is a linked category.
  - Others list their apps.
- **Base collections:** the burnt-in `storeAppsCollections` (collectionId, title key, linkedEntities, group, order, feedOrder, activeFlags, nav…). The content doc overrides order, title and visibility per id (the worker's merge `_`).
  - Linked entities name catalog categories.
  - copilotplugins links `cp_copilotExtensions` when enableCopilotExtensions and enableStoreWorkerDataProvider are on, otherwise `cp_copilotPlugins`.

### Ranked catalog
- **Request:** `POST {middleTier}/beta/users/apps/store` with headers `x-client-ui-language`, `x-ms-client-caller` and `x-ringoverride`. The body is:
  - `appCategories[]` and `defaultAppsSortType: "RankedByLocale"`;
  - `appsStoreOptions {includeIndustries, includeSuggestedApps, includeSubscriptionApps, includeTotalAppsCount, includeFrequentCollaboratorsApps, includePluginsForCopilot, includePreinstalledApps, includeAgentBlueprints}`.
- **Reply:** `appCategoriesDictionary {category: {apps[{id, metaCapabilities, ranking, rating{average, count}, version}], totalAppsCount, blockedAppsCount}}`.
  - `all` and `popularApps` hold the whole ranked catalog (3305 apps).
  - The `cp_*` capability categories come back only with an `appFilter`.
- **Search:** `POST {middleTier}/beta/users/apps/search` with `{searchQuery, includeOpenAiPlugins, includeSharedApps}`.
- **App fields** (name, developer, icon, descriptions, scopes) come from the catalog definitions (`beta/users/apps/definitionsv2`, see app-details.md).

## 3. In-context Store ("Add agent to the chat", `in-context-store-dialog`)

- **Opens from** the @ picker's "Add agent to the chat" (group chats) or "Add agent to the channel".
- **Collections:** ECS `extensibility.inContextStoreCollectionIdsOverwrite[kind]` gives the ids in order (`app:co:{collectionId}`).
  - The kind is `BotGroupChat` for a group chat and `BotTeam` for a channel.
  - For ost-test1, BotGroupChat is copilotplugins, tenantapps, suggestedapps, abcbot4, popularapps, abcbot1, productivity, abcbot2, abcbot3, microsoft, education. A collection hidden in the Store still shows here.
- **Apps:** only apps whose bot supports the conversation's scope (GroupChat; Team for channels). For example:
  - Workday, ServiceNow Otto, monday.com, Dropbox and Mural are Personal-only and were left out of Agents;
  - Jira, Confluence Cloud, Adobe Acrobat, Box, Asana and so on kept the catalog ranking.
- **Layout** (CSS px; the dialog is 901.3 × 647.3, radius 8, white):
  - **Search box:** "Search for agents and bots", 836 × 32 at (32, 32), #F5F5F5, radius 4, search icon 20 at the right. The focus line is brand.
  - **Top grid** (`in-context-grid`): 100 × 96 tiles (radius 6). Each has a 48 px round icon 6 down and the name 12/16, centred. It shows the bots the user already has (Power BI, Updates).
  - **Divider:** "Add a new agent or bot" (16/16 semibold #424242) on a centred rule.
  - **Each collection:**
    - a header row 78 tall: title 12/16 semibold (H2) and "See all" (12/16 semibold #4F52B2) at the right;
    - three cards 834 × 86, 12 padding, radius 4, white (hover #F5F5F5), 98 apart;
    - each card has a 32 px round icon, the name 14/20 bold, a 20 px badge (agent sparkle), the short description 12/16 and the rating (16 px star, bold average 12/16 and "(N ratings)").
  - **Footer** (60 tall): manage-apps (32 × 31.3, bottom left), Close (96 wide) and "Get more apps" (brand, 118.8 wide).
- **See all:**
  - The heading is the collection title, 12/24 semibold.
  - The full list follows, in cards 848 × 122 with 134 between them. Each card has the developer (12/16) under the name, the description at 166 and the rating at 192.
  - A Back button sits at the bottom left.

### Adding an agent (captured on winpc, adding Polls to OST group test)
- Clicking a card opens the app's details in place of the Store. A back arrow at the top left returns to the Store. "Add" adds the app to the conversation.
- **Requests:**
  - `POST {mt}/beta/users/apps/entitlements`, for you (when you don't have the app);
  - then `POST {mt}/beta/chats/{threadId}/apps/entitlements`. For a channel this is the team's endpoint, with `X-Ms-Appinstall-Channelid`.
  - Each body is the app's definition (as batchedDefinitions returns it). Each reply is `{value: {id, state: "Installed", installedVersion, …}}`.
- **Afterwards:**
  - A bot that only sends notifications gets "About this bot": "This bot sends notifications only. You're not able to chat with or @mention it." with OK.
  - Other bots start an @mention in the compose box.
- **In the chat:**
  - The bot's own AddMember / DeleteMember events are not shown.
  - The app's events are shown instead: `ThreadActivity/AddCustomApp` reads "{name} added **{app}** here." and `DeleteCustomApp` reads "{name} removed {app} from the chat.", both with the Apps icon.
  - The first time, Teams may add "Try an action below to see how it works." with the app's action buttons.
- **Manage apps ▸ Remove** sends `DELETE {mt}/beta/chats/{threadId}/apps/entitlements/{appId}` after "Remove {app}? Are you sure you want to remove {app}?".

## 4. The Store (Apps)

Measured on winpc on 2026-11-09. OST: `StoreView.qml`, plus `store_home`, `store_page` and `search_store` in `api::store_content`.

### Header
- 60 tall: "Store" (18/24 bold), then the tabs Home, Featured ▾ and Categories ▾ (14/20, 12 × 10 padding, brand underline), then Devices ▾ and the "Manage your apps" button.
- **Featured** is a 256-wide menu of the collections with `navSection` "featured", grouped by `navSubSection` (divided) in `navSectionOrder`: Built for your org | Agents | Popular on Teams, Trending with your peers.
- **Categories** lists the category groups (content `navSection` "category") alphabetically: Business operations, Content and collaboration, Data and learning, IT and developer tools, Navigation and mapping, Productivity, Support and tools.
- Menu icons come from `storeGroupCollectionIconMap`, by "app:co:{id}" or by title key: Guest, Agents, StarEmphasis, ArrowTrending, Building, ChatMultiple, DataPie, Code, Map, Briefcase, Headset.

### Banner
276 tall, lavender:
- "Do more in Teams" (40/56 semibold);
- "Discover agents and apps that can help you tackle any task." (14/20);
- a 530 × 48 pill search, "Search agents and apps".

### Feed
- The collections with `isInFeed`, by `feedOrder`. The content doc overrides the burnt-in placement and description.
- For ost-test1 the feed is:
  - Added by your org
  - Popular on Teams
  - Agents We Love
  - Productivity tools
  - Built by Microsoft
  - Project management
  - Create effective online surveys
  - Review and approve leaves
  - Education
- Each collection is 90 in:
  - the title (18/24 bold) at 26;
  - the description (14/20 #424242) at 54;
  - "See all" (14/16 semibold, brand) at the right.
- Then up to nine apps, three to a row from 92. Cards are 330 × 128 (104 without ratings), 16 apart, radius 12, with a hover fill. Each card has:
  - a 52 px squircle icon at (16, 16), with a 24 px check circle when you have the app;
  - the name (16/20 semibold) at (84, 21);
  - two lines of description (14/20) at 45;
  - the rating (12/16) at 91. `disableRatings` collections (your org's) leave it out.

### Pages
- See all, a menu entry and search open a page: Back (32), the title (30/36 semibold) and the description (16/22).
- Then cards 340 apart, with the developer (12/16) under the name. A category group instead shows its child collections as on the feed.

### The Store doc path depends on the licence
- For SMB users, Teams asks for `apps/smb/…`. Without authz `licenseDetails` OST asked for the Enterprise doc instead, which has different collections and featured entries.
- OST now fetches `licenseDetails` when the config lacks them (`api::ecs::license`).

## 5. Devices (Teams' device store; measured on winpc 2026-11-20, TASK-0077)

OST: `api::devices`, `StoreView.qml` (device pages, the band, the filter),
`DeviceDetailsDialog.qml`, `DeviceCartDialog.qml`, `--store-devices-test`.

### Data
- **Catalog** (no sign-in): with ECS `marketplace.enableCatalogOneCdn` (on),
  `GET {catalogOneCdnBaseUrl}/{catalogOneCdnVersionTTL}/pointer` (e.g.
  `https://res.cdn.office.net/devicescatalog/5mttl/pointer` → `"2026/11/20"`),
  then `…/{catalogOneCdnTTL}/{version}/US_en-us/AllDevices` (510 devices:
  `deviceId, deviceName, manufacturerName, shortDescription, thumbnailImage
  {blobURI, altText}, price, collections[], isFeatured, availabilityStatus,
  certifiedDate, connectionType, wearingStyle, useCase, color,
  accessoryType, fulfillerPartner "UC"…`) and `…/US_en-us/{deviceId}` (one
  device: also `fullDescription`, `images {small, medium, large, actual}`,
  `overview [{Key, Value}]` (Highlights), `techSpecs [{Key, Value}]`).
  Without OneCDN: `{deviceStoreCatalogCDNHost}/catalogdata/US_en-us/AllDevices`.
- **Collections** (ECS `extensibility.storeDevicesCollections`, worker module
  2636): featured 24 (lists `isFeatured`), headsets 9, webcameras 5,
  speakerphones 8, deskphonesandteamsdisplays 7, monitors 11, teamsrooms 6,
  roomsystemsaccessories 10; titles and descriptions are Teams' strings;
  icons (storeGroupCollectionIconMap) Star, Headset, Video, Speaker,
  DeviceMeetingRoom, Desktop, SurfaceHub, DeviceMeetingRoomRemote.
- **Order**: Teams' default sort Availability (Available, LowStock,
  AvailableIn3Weeks, OnBackOrder, OutOfStock, the rest), then the device id
  compared as text (Headsets: 100, 1000, 1004, 1021 …). 147 headsets; 24
  shown, more as you scroll.
- The market: the United States ("USA"; tooltip "Your region is set to
  United States."); prices as `Intl.NumberFormat("en-US", currency USD)`.

### Layout (CSS px, the area right of the app bar)
- The header's Devices ▾ menu (247 wide, 32 px items with their icons).
- A device page: a 28 tall #F5F5F5 band under the header: globe 16, "USA"
  (14/20 semibold #424242), the cart pill flush right (brand, 43.8 x 24, a
  20 px cart and the count 12/16 white). Then, on the lavender page: Back at
  (45.5, 62), the title (30/36 semibold) at (85.5, 60), the description
  (16/22, 580 wide) at 108; the filter button (32, round) 64 under it,
  96.5 from the right; the tiles 74 under that: 239 x 312, radius 12, 255
  apart, four to a row 323 apart: the picture 207 x 160 on white (radius 4)
  at 16, the name 12/16 semibold at 188, the maker 12/16 at 208, the price
  14/20 bold at 232, the short description 12/16 (two lines) at 264.
- Its filter shows Teams' generic tree with only an empty "App features"
  group (Filter / Clear, the group's checkbox); nothing filters (as Teams).
- **Details** (a 720 x 640 dialog): Close (16 px) at (667.3, 20.7); the
  large picture 324.3 x 186.4 at (32.7, 48.7); at 407.3: the name 18/24 bold,
  the maker 14/20 #616161, the price 18/24 bold, "Free shipping in most of
  the US" (12/16 semibold, a van in a 24 px #E8EBFA circle, an info button),
  "Quantity" 12/16 over a 112 x 31.3 dropdown (1–9, 10+) and Share ▾ (Copy
  Link), then Add to cart (112 x 31.3 brand); once in the cart, View Cart
  (brand) and Add to cart (outline). The tabs Overview, Highlights, Tech
  Specs (14/20, 44 tall) at 368.7 scroll to their sections (Overview: the
  short description 14/20 bold and the full one; Highlights: each Key bold
  over its Value; Tech Specs: a table, key 14/20 semibold, value at 162,
  rows on #FAFAFA with hairlines). Footer 72 tall: "Powered by
  UnifiedCommunications.com". Scrolled, Teams pins a compact header (the
  thumbnail, "<maker> - <name>", price, quantity, Add to cart, the tabs);
  OST does too.
- **Cart** (720 x 640): "Your cart" 18/22 bold; columns Item, Item Price,
  Quantity, Price (12/16 #616161); rows 96.7 tall (picture 92.5 x 56.1, name
  14/20 semibold, price, a 83.5 wide quantity dropdown, Delete, the line
  price 14/20 bold); Subtotal with "US" and the amount (18/20 bold),
  "Shipping and taxes will be calculated at checkout."; footer "Powered by
  UnifiedCommunications.com." Privacy | Terms of service
  (unifiedcommunications.com/docs/teams-marketplace/en-us/…) and Checkout
  (265 x 31.3). Empty: "Your cart is empty", Continue shopping.
- The cart lives on the device (Teams' IndexedDB store cart per market; OST
  keeps it in its settings). Checkout (not pressed on winpc) opens Teams'
  DeviceStoreCart dialog with the Client Store app (ECS
  `marketplace.appManifestUC`, personal tab
  `https://clientstore.unifiedcommunications.com/`) in its host, which reads
  the cart with TeamsJS `marketplace.getCart` (answered `[null, cart]`) and
  may change it (`addOrUpdateCartItems`, `removeCartItems`,
  `updateCartStatus`). OST hosts it the same way (app_host.js); unverified
  past opening, since checking out would place an order.

## 6. See all filter (measured on winpc 2026-11-20)
- The collection filter (`collection-filter`, a 32 px round button, 96.5
  from the right, 64 under the page's description) opens Teams' filter tree
  (`store-collection-filter-tree`): "Filter" (14/20 bold) and "Clear" (14/20
  semibold, #BDBDBD until something is picked), then 220 wide columns:
  Availability (Ready to add, Requires approval), Pricing (Free to add,
  Subscription plans available), Certification (Microsoft 365 certified,
  Publisher attested), Supported Channel (Shared Channel, Private Channel)
  in one, App features (Bot, Connector, Agent, Group Chat, Meeting,
  Messaging, Personal, Tab) in the other; each group's title row (14/20
  semibold) checks all its options; rows 34 tall with the 16 px checkbox
  (#616161 edge, radius 2; brand when on) at 184. Only options the page's
  apps have are listed.
- An app's features (worker `KDr`): Personal (every static tab personal),
  Connector, Shared/PrivateChannelTypeSupported (supportedChannelTypes),
  Available / Blocked, Bot, MessageExtension, Tab (+ Meeting for a group chat
  tab in meetingSidePanel / meetingStage), Free / Paid (subscriptionOffer),
  Certified / PublisherAttested (securityComplianceInfo.status),
  CopilotPlugin (copilot capabilities). OST: `store_content::app_features`.
- The page keeps apps with **any** picked option (the worker's
  includedFeatures). Picked options show as pills (brand, 25 tall, radius
  12.5, 14/20 white) left of the button; a pill removes its option. The
  button reads "Filter (n), n filters applied".

## 7. Header buttons, Manage your apps (measured on winpc 2026-11-20)
- At the header's right, 32 x 33.3: "Your agents and apps" (library, 84
  from the right) and "Manage your apps" (gear, 48 from the right). On a page
  the search moves into the header (384 x 32, radius 16, 96 from the right).
- **Your agents and apps**: a page ("See all the apps and agents you added,
  your org added for you, or people shared with you.") with chips Added by
  you, Created by you, Added by your org, Built for your org, Shared with
  you, and your apps as cards.
- **Manage your apps** (GraphQL installedAppsForUser; OST
  `api::manage_apps`, `ManageAppsView.qml`, `--manage-apps-test`): Back, the
  gear tile, "Manage your apps" and the Apps tab; Get more apps, Upload an
  app, Sort (Recently used, A-Z, Z-A), Find by name; rows 65 tall (caret,
  36 px icon, name 14/20 bold, publisher 14/16 #616161, ··· = View details,
  Copy link). The list: personal entitlements Installed / AdminPreInstalled /
  InstalledAndFavorited / PreConsented, apps shared with you (`GET
  {mt}/beta/users/apps/entitlements`, enableSharedInstalledAppsInManageApps;
  a shared copy of an Office asset you have shows once), and apps installed
  in your teams (TASK-0237: the same `aggregatedEntitlements` POST with your
  teams' threads as the body answers `teamsEntitlements` {thread: [{id,
  state}]} with the definitions; `GET {mt}/beta/chats/{team thread}/apps/
  entitlements` only gives the tenant's permanent apps, so SharePoint Pages,
  Forms, Lists and the SharePoint tab app were missing; Installed /
  AdminPreInstalled / InstalledAndFavorited); the multimodal AI bot hidden.
  Sorted by your apps usage (`beta/users/apps/usage` `apps`, the order
  Teams keeps), the rest after in Teams' insertion order (shared, personal,
  then your teams' apps), updates first. Expanded: "Recently used" (i) then "Personal app" and each team
  with Remove (`DELETE {mt}/beta/{users|teams/{thread}}/apps/entitlements/{app}`
  after "Remove {app}?").
- Upload an app: a 600 wide dialog with one card, "Submit an app to your
  org" (a .zip for your admin: `POST {mt}/beta/users/tenantapps/definitions/
  appPackage`, uploadTenantStagedApp). Not submitted from OST in tests.

## 8. App bar and View more apps (measured on winpc 2026-11-20, TASK-0238)

**Data.** The bar and its flyout are your personal apps: `POST {mt}/beta/users/
apps/aggregatedEntitlements?appbarview=userpinned` (body `[]`), each
entitlement with `isAppBarPinned` and `appBarOrder`. The bar shows the pinned
ones by order (Activity 1, Chat 3, Chat-separate 4, Teams 5, Calendar 6, Calls
7, OneDrive 8, Copilot 9 for ost-test1), View more apps the rest. Core ids
(async-entry module 318854): activity 14d6962d…, chat (separate view)
86fcd49b…, simple collab (unified Chat) 3b64df9d…, channel (Teams)
2a84919f…, calendar ef56c0de…, calling 20c3440d…, files 5af6a76b…, Events
a63f7012…, People 7831feaf…, Meeting Recaps 981bbfd0…, Store ac40aa4a…,
Copilot b5abf2ae… (a platform app). Store keeps its own place after the
pinned apps; Copilot opens the Microsoft 365 Copilot app's page full screen.

**Pinning** (worker `appBarManager`; captured): Pin gives the app the highest
order + 1; Unpin removes it and moves every app after it up one; Move up /
Move down give the app its visible neighbour's order (`reorderApp`: the apps
in between shift one). Each change posts `POST {mt}/beta/users/apps/pinned
{"appBarPinnedApps": [{appId, appBarOrder}, …]}` with the changed apps first,
then every other pinned app; unpinned ones are left out. E.g. Calendar 6 ▸
Move up (unified view, neighbour Chat 3): Calendar 3, Chat 4, Chat-separate 5,
Teams 6.

**Store's Unpin** is the appBar client preference `isStoreUnpinned` (kept on
the device); Store then is the flyout's last row under a divider, with Pin.

**The tile menu** (TileContextMenu, 180 wide here; beside the bar, centred
on the tile): groups split by dividers — Open in new window | About, Share
app, the app's own actions (Chat: New message Ctrl+N, New message in new
window Ctrl+Shift+N; bots: Block bot conversation) | Move up, Move down (not at
the ends), Pin or Unpin | Uninstall | Customize app bar. About and Share app
only for platform apps (OneDrive, Copilot, Word…), not core ones; Uninstall
only when Teams' canBeUnacquired: not core and the state isn't
InstalledAndPermanent, AdminPreInstalled or RequireConsent. View more apps'
rows have the same menu without moves and Customize app bar (Events: Open in
new window, Pin; People and Meeting Recaps: Pin). Icons: open-window,
info, share-invite, arrow-up, arrow-down, pin / pin-off, delete, settings.

**Uninstall** asks "Remove {app}" / "Are you sure you want to remove {app}?"
(Cancel, Remove; 420 wide), then `DELETE {mt}/beta/users/apps/entitlements/
{app}` and reloads your apps.

**Open in new window** is on platform apps with a personal tab (Teams'
enablePersonalAppsPopOut) and on the core apps ECS `core.allowedCoreAppsPopOut`
names (simple collab, chat, channel, activity, calling, events; Calendar via
the M365 calendar's own action). Measured on winpc 2026-11-20: each opens a
946 x 593 window with Teams' 32 px child-window title row (the app's name,
Settings and more) and no app bar; Chat: the whole chat list (280 wide), the
picked chat's header (61) and messages beside it; Activity: the feed (280)
and the item beside it; Calls: its page as in the main window.

**Block bot conversation** (Unblock when blocked) follows About and Share app
for a platform app with a bot when you have a 1:1 chat with that bot (Teams'
hasBotChat; ECS enableBlockUnblockBotChatForPersonalApps). It sets the chat
thread's `messagingdisabled` property: `PUT {chat}/v1/threads/{chat}/
properties?name=messagingdisabled {"messagingdisabled": "true"}` ("false" to
unblock). The conversations list leaves that property out, so the state is
read from `GET /v1/threads/{chat}`.

**Customize app bar** opens Settings ▸ Appearance (`openSettingPage`,
settingId `app-bar-settings`) with the App bar card in view and focus on Show
app names' switch (its focus outline drawn).

**The flyout**: 300 wide, centred on View more apps, a 268 x 32 search box 15
in and 13 down, rows 269 x 40 on a 42 px pitch from 55 (eight in view, the rest
scroll): a platform app's colour icon (24), a core app's glyph in a bordered
28 px tile, the name at 42.
