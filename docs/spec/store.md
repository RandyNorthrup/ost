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
