# Teams' host for embedded app pages (TeamsJS) — spec

Measured in Teams on the web (teams.cloud.microsoft, the same React client
as Teams desktop) as ost-test1 on 2026-11-16, running inside OST's own web
profile on linuxlt and read over its DevTools port: every frame hooked, the
`message` events each one received logged (tokens redacted), the token
requests' parameter names and non-secret values recorded, and Teams' own
host code read from its bundles (modules 126552 NAA handler, 764290 message
processor and valid-domain rules 9883, 711436 NAA executor, 985817 hosted
web content). Pages hosted: the channel Notes tab of OST Test Team
(General, provisioned; OST test channel 2, first opening) and the Outlook
calendar frame Teams keeps.
OST: `desktop/src/app_host.js`, `WebApp.qml` (`teamsHost`),
`api::app_host`, `auth::broker`, `api::tab_add::set_settings`,
`--app-host-test`.

## How Teams frames an app
- The app's page is an iframe in Teams' own page, so the frame's parent and
  top window are Teams (origin `https://teams.cloud.microsoft`; desktop
  Teams' is its own Teams origin):
  `<iframe id="cacheable-iframe:<app id>" data-tid="hwc-iframe"
  data-inp="cacheable-iframe" name="embedded-page-container" title="<tab
  name>" data-appid data-sessionid data-uuid allowfullscreen="true"
  style="border: 0px; width: 100%; height: 100%; visibility: visible;">`.
  - sandbox: `allow-storage-access-by-user-activation allow-scripts
    allow-same-origin allow-top-navigation-to-custom-protocols allow-forms
    allow-popups allow-popups-to-escape-sandbox allow-pointer-lock
    allow-modals` (`allow-downloads` too for Storyline);
  - allow: `clipboard-write *; media-playback-while-not-visible 'none';
    local-network-access *; camera *; microphone *; encrypted-media *;
    speaker-selection *;` (the last four for apps with device permissions).
- A channel tab's frame fills the tab under the channel header: 864 x 555
  at (348, 145) in a 1212 x 700 window (parents persisted-app-content-main,
  slot-measurer, app-layout-area--main, all the same box).
- The frame is **cached per app** ("cacheable-iframe"): opening another
  channel's Notes reuses it. Teams posts `beforeUnload`; the app answers
  `readyToUnload`; Teams posts `load` with `[{entityId, contentUrl}]`
  (the address with every placeholder filled) and the app navigates
  itself.
- The address is the tab's stored content address with Teams'
  placeholders filled from the app's context, URL-encoded: `{locale}`,
  `{tid}`, `{upn}` / `{userPrincipalName}`, `{groupId}`, `{theme}`,
  `{entityId}`, `{subEntityId}`, `{sessionId}`, `{ringId}`,
  `{teamSiteUrl}`, `{channelType}`, `{appSessionId}`, `{hostClientType}`,
  `{channelName}`, `{teamType}`; also TeamsJS 2's dotted names (Copilot's
  address: `{user.id}`, `{user.tenant.id}`, `{app.host.name}`,
  `{app.host.clientType}`, `{app.theme}`, `{app.host.ringId}`,
  `{app.host.sessionId}`; Teams leaves one it has no value for, such as
  `{page.renderingSurface}`). Unfilled, Copilot's server sends the page to
  `/hosted/semanticoverview/Users('OID:{user.id}@{user.tenant.id}')`,
  which fails ("Don't know how to locate "default" implementation of
  interface 274d7ae9-…", checked in OST 2026-11-16).

## Which host origins apps accept
- TeamsJS in the app takes messages only from its parent (or opener) and
  only from an origin in its valid-origins list (teams.microsoft.com,
  teams.cloud.microsoft, *.office.com, *.microsoft365.com, … or the CDN
  list); an app may add its own (`initialize`'s third argument; the
  ChannelNotes page passes `["https://teams.microsoft.com"]`).
- MSAL's NAA bridge in a deeper frame (OneNote's WOPI frame
  `oauth.officeapps.live.com`, OneNote add-ins on
  `fa000000128.resources.office.net`) is polyfilled there with the
  *top* origin it is given; it posts to `window.top` with that origin as
  target and accepts answers only from it (Office's sharedauthclient,
  `nestedAppAuthBridge`). So the top window must be Teams' origin too.
- The pages' servers allow framing only by Teams' origins
  (frame-ancestors), so the frame's ancestors must be a Teams origin.

## The message protocol
Requests are objects posted to the parent (TeamsJS 2.x):
`{id, uuidAsString, func, args, timestamp, monotonicTimestamp,
apiVersionTag, isProxiedFromChild, teamsJsInstanceId}` (NAA also `data`).
Teams answers on the same window with the request's origin as target:
`{id, uuidAsString (from the request's uuid or uuidAsString), args,
origin: <the app's origin>, monotonicTimestamp}`. Teams' own requests to
the app (events) are `{func, args?, monotonicTimestamp}`. A func Teams
doesn't handle gets no answer.

| func | args | Teams answers |
|---|---|---|
| `initialize` | `[version, apiVersion 4, validOrigins]` | `[frameContext ("content"), hostClientType ("web"; desktop on Teams desktop), "2.0.0", runtime JSON]` |
| `getContext` | `[]` | `[context]` (below) |
| `authentication.getUser` | `[]` | `[true, {loginHint, oid, tid, upn, dataResidency: "public"}]` |
| `registerHandler` | `[name]` (load, beforeUnload, themeChange, focusEnter, log.request) | none |
| `appInitialization.appLoaded` | `[version]` | none |
| `appInitialization.success` | `[version]` | `[null]` (runtime `app.notifySuccessResponse`) |
| `nestedAppAuth.execute` | `[]`, `data`: the NAA request string | `[null, NAA response string]` |
| `nestedAppAuth.manageNAATrustedOrigins` | `[{action: ADD/DELETE, appOrigins}]` | `[{status: "success"/"limited"(, deleted)}]` (Microsoft-owned apps only) |
| `settings.setSettings` | `[{entityId, contentUrl, websiteUrl, removeUrl, suggestedDisplayName, …}]` | `[true]` once saved |
| `readyToUnload` | `[]` | none (Teams then posts `load`) |
| `conversations.closeConversation` | `[]` | none |
| `settings.setValidityState` | `[valid]` | none (Teams turns Save on or off) |
| `registerHandler` `save` | (pages.config.registerOnSaveHandler) | none; Save posts `{func: "settings.save", args: [{}]}` |
| `settings.save.success` | `[]` | none; Teams then adds the tab |
| `settings.save.failure` | `[reason]` | none; Save stays |
| `getChatMembers` | `[]` (in a chat) | `[{members: [{upn}, …]}]` |
| `copilot.eligibility.getEligibilityInfo` | `[null]` | `[{cohort: "bcais", ageGroup: null, isCopilotEnabledRegion: true, isCopilotEligible, isOptedOutByAdmin: false, userClassification: {persona: "other"}, featureSet: {uxFeatures: [], serverFeatures: []}, settings: {conversationSettings: {isOptionalConnectedExperiencesEnabled: null}}}]` |
| `tasks.startTask` | `[taskInfo {url, title, width, height, …}]` | when the dialog closes: `[null, result]` (submitted) or `["User cancelled/closed the task module.", undefined]` |
| `tasks.completeTask` | `[result, appIds]` (from the dialog's page) | none; the dialog closes |
| `tasks.updateTask` | `[{width, height}]` | none; the dialog resizes |
| `messageForParent` / `messageForChild` | `[message]` | none; passed to the opener's / dialog's frame as an event of that name |
| `readyForUrl` (Whiteboard) | `[]` | `[]`, then the event `updateBoardContentFromTeams ["[]", ""]` |
| `loadingCallback` (Whiteboard) | `[success, errorMessage?]` | `[]` (Teams logs it) |
| `changeWhiteboardUrl` (Whiteboard) | `[url, passThrough?]` | `[]`; Teams keeps the board for the meeting (below) |

The runtime Teams answers (apiVersion 4):
`{apiVersion: 4, hostVersionsInfo: {adaptiveCardSchemaVersion: {1, 5}},
canParentManageNAATrustedOrigins: true, isDeeplyNestedAuthSupported: true,
isNAAChannelRecommended: true, supports: {app: {notifySuccessResponse},
appInstallDialog, appEntity, call, chat, clipboard, conversations,
copilot, dialog: {url: {bot, parentCommunication}, card: {bot}, update},
externalAppAuthentication(+ForCEA), externalAppCardActions(+ForCEA,
+ForDA), externalAppCommands, files, hostEntity, interactive, logs,
marketplace, media, meeting, messageChannels: {telemetry, dataLayer},
monetization, nestedAppAuth, otherAppStateChange, pages: {appButton,
backStack, config, fullTrust, tabs, currentApp}, people, permissions,
remoteCamera, sharing: {history}, stageView: {self}, store, teams:
{fullTrust: {joinedTeams}}, teamsCore, thirdPartyCloudStorage, webStorage,
shortcutRelay}}`.

The context for the General channel's Notes tab: `locale "en"`,
`appSessionId`, `appLaunchId`, `appId`, `theme "default"`,
`appIconPosition -53`, `osLocaleInfo {platform "windows", regionalFormat
"en-us", shortDate "M/d/yyyy", longDate "dddd, MMMM d, yyyy", shortTime
"h:mm tt", longTime "h:mm:ss tt", timezone}`, `parentMessageId ""`,
`userClickTime`, `userClickTimeV2 0`, `userFileOpenPreference "inline"`,
`manifestVersion "devPreview"`, `hostName "TeamsModern"`, `hostFeatures
{nestedWildcardsInValidDomains false, serverSideRendering false}`,
`hostClientType`, `sessionId`, `ringId`, `hostAncestors ["TeamsModern"]`,
`entityId` (the tab's), `frameContext "content"`, `subEntityId ""`,
`isFullScreen false`, `isMultiWindow false`, `isBackgroundLoad false`,
`sourceOrigin ""`, `userObjectId`, `userLicenseType`, `loginHint`,
`userPrincipalName`, `upn`, `userDisplayName ""`, `tid`, `tenantSKU
"enterprise"`, `channelId`, `channelName`, `channelRelativeUrl`
(the channel thread's `channelDocsFolderRelativeUrl`), `channelType
"Regular"`, `defaultOneNoteSectionId ""`, `chatId ""`, `meetingId ""`,
`teamId` (the team's thread), `teamName`, `teamType 0`, `groupId`,
`isTeamArchived false`, `userTeamRole 0` (owner; 1 member, 2 guest),
`teamSiteId ""`, `teamSiteUrl`, `teamSiteDomain`, `teamSitePath`.

## Nested app authentication (NAA)
- Requests: `{messageType: "NestedAppAuthRequest", method, requestId,
  sendTime, clientLibrary: "msal.js.browser", clientLibraryVersion,
  tokenParams: {clientId, scope, correlationId, authenticationScheme
  "Bearer", extraParameters, claims?, authority?, platformBrokerId?,
  forceRefresh?}}`; methods GetInitContext, GetToken, GetTokenPopup.
- From the app's own frame (`isDeeplyNestedRequest` false) and from any
  frame nested in it, which posts straight to the top window. Nested
  frames may only call `nestedAppAuth.execute`.
- Trust (Teams' `isTrustedOrigin`): the asking origin matches the app's
  valid domains (its definition's `validDomains` plus the hosts of its
  tabs' addresses; `^https://<domain>((/|\?).*)?$`, `*` = one label), or
  the app added it with `manageNAATrustedOrigins`. Trust only decides
  whether GetInitContext tells the account; tokens are minted either way.
- Answers (`NestedAppAuthResponse`):
  - GetInitContext: `{success: true, initContext: {sdkName: "Teams Auth
    SDK", sdkVersion: "V1", accountContext?: {homeAccountId (the user's
    object id), tenantId, environment: "login.microsoftonline.com"}}}`;
  - GetToken / GetTokenPopup: `{success: true, token: {access_token,
    id_token, expires_in, scope (as asked), account}, account}`, the
    account `{homeAccountId, environment, username, name, __typename:
    "NestedAppUser"}`;
  - errors: `{success: false, error: {status, isExpected, code, subError,
    description}}` with status USER_INTERACTION_REQUIRED, USER_CANCEL,
    NO_NETWORK, TRANSIENT_ERROR, API_CONTRACT_VIOLATION,
    NESTED_APP_AUTH_UNAVAILABLE or PERSISTENT_ERROR; a request without
    client or scope gets `{status: API_CONTRACT_VIOLATION, isExpected:
    true, description: "Missing parameters."}`.
- The token request (Teams' worker, then AAD): `POST
  login.microsoftonline.com/{tenant}/oauth2/v2.0/token?client_id=<app>&brk_client_id=5e3ce6c0-…&brk_redirect_uri=https://teams.cloud.microsoft/v2/authv2`
  with `grant_type=refresh_token`, `client_id=<app>`, the hub's refresh
  token, `scope="<scope> openid profile offline_access"`,
  `redirect_uri=brk-multihub://<the asking frame's host>`,
  `client_info=1`, `claims` when asked, `brk_client_id`,
  `brk_redirect_uri`. Seen for the Notes tab:

| asking frame | client | scopes |
|---|---|---|
| www.microsoft365.com (officeunihost) | fd5f78f6-a28f-450b-abc7-777f3dbbfcba | `https://onenote.com//.default` (GetTokenPopup), `https://{tenant}.sharepoint.com/.default` |
| m365.cloud.microsoft | fd5f78f6-… | `https://{tenant}-my.sharepoint.com/.default` |
| www.onenote.com (ChannelNotes, first opening) | 2d4d3d8e-2be3-4bef-9f87-7875a61c29de | `https://onenote.com//.default`, `https://{tenant}.sharepoint.com/.default` |
| oauth.officeapps.live.com (WOPI, trusted by ADD) | 243c63a3-247d-41c5-9d83-7788c43f1c43 | `e03a13ee-…/.default`, `https://augloop.office.com/v2/.default`, claims xms_cc CP1 |
| fa000000128.resources.office.net (add-ins, not trusted) | c0ab8ce9-e9a0-42e7-b064-33d422df41f1 | substrate, graph, loki, augloop, ic3, clients.config, titles.prod.mos, … |

## The channel Notes tab on that host
- The tab's stored address is OneNote's ChannelNotes page until the
  channel has notes: `https://www.onenote.com/teams/ChannelNotes?ui={locale}&tenantId={tid}&upn={upn}&groupId={groupId}&theme={theme}&entityId={entityId}&subEntityId={subEntityId}&sessionId={sessionId}&ringId={ringId}&teamSiteUrl={teamSiteUrl}&channelType={channelType}&trackingId={appSessionId}&hostClientType={hostClientType}&channelName={channelName}&teamType={teamType}`,
  entityId `NOTES`, `isUnconfigured: "True"` in its thread property.
- **Provisioning** is that page's (OneNote's), not Teams': it shows
  "Getting the Notes tab ready. This can take a few seconds..." (the
  OneNote tile with an hourglass, a spinner), then through the OneNote API
  (www.onenote.com/api/v1.0, its NAA tokens): `POST
  me/notes/notebooks/Microsoft.OneNote.Api.GetNotebookFromWebUrl()`
  `{"webUrl": "<site>/SiteAssets/<Team> Notebook"}`, `GET
  …/notebooks/{id}?$expand=sections,sectionGroups`, `POST
  …/notebooks/{id}/sections {"name": "<channel name>"}`, `POST
  …/sections/{id}/pages`; then `settings.setSettings` with the new
  `entityId` (`NOTES_<guid>`), `contentUrl` (the officeunihost page with
  the notebook, section and placeholders), `websiteUrl
  "https://onenote.com/"`, `removeUrl ""`, `suggestedDisplayName "Notes"`,
  `notebookSource`, `apiUrl`.
- Teams saves that as the tab's channel-thread property (`PUT
  {chatsvc}/v1/threads/{channel}/properties?name=tab::{id}`):
  `{"id","name","definitionId","directive","tabType":"tab:","order":10000,"replyChainId":0,"settings":{"url","websiteUrl","entityId","subtype":"extension","removeUrl"}}`;
  the middle tier then lists it with `configuration {entityId, contentUrl,
  websiteUrl, removeUrl}`. It answers `[true]`, posts `beforeUnload`, and
  on `readyToUnload` posts `load` with the new address.
- The provisioned page: `https://www.microsoft365.com/launch/onenote/officeunihost/teams?auth=2&flight=officeunihost&notebookSource=DefaultNotes&notebookSelfUrl=…&oneNoteWebUrl=…&notebookName=Notes&createdTeamType=Standard&oneNoteClientUrl=…/<channel>.one&subEntityId=…&sectionId=1-…&notebookIsDefault=false&isMigrated=1&<placeholders>`.
  It calls initialize, getContext, NAA GetInitContext / GetTokenPopup /
  GetToken, registerHandler (log.request, load, beforeUnload,
  themeChange, focusEnter), authentication.getUser, appLoaded, success,
  conversations.closeConversation, manageNAATrustedOrigins ADD
  `https://oauth.officeapps.live.com`, and frames OneNote for the web
  (`usc-onenote.officeapps.live.com/o/onenoteframe.aspx`), which shows the
  notebook header ("OST Test Team Notebook"), the ribbon, the page list
  (+ Add page, "Untitled Page") and the page (title, date and time line,
  body), editable.
- Its tab menu on Teams on the web: Expand tab, Reload tab, Open in new
  window (`goToWebsite`, the tab's websiteUrl), Copy link to tab, Rename,
  App permissions, About this tab, Move left, Move right, Remove (177.6
  wide, 32 px items). Teams desktop's menu for this extension tab (module
  542104, desktop host) has Open tab in new window (popOut) and Open in
  browser instead (channel-tabs.md).

## Other pages seen on the host
- **Storyline** (chat tab, app 683f3525): initialize, registerHandler
  (beforeUnload, load, themeChange, backButton, focusEnter,
  shortcutRelay.hostShortcutChanged), getContext, NAA GetInitContext /
  GetToken (client f4060917, `https://engage.cloud.microsoft/teams-branded-exp/access_as_user`,
  loki and augloop scopes), appLoaded, `shortcutRelay.getHostShortcuts`
  (answered `[{shortcuts: [Teams' list], overridableShortcuts: []}]`),
  success. Context: entityId `storyline`, `chatId`, `meetingId` =
  base64 of `0#<chat id>#0`, `channelId ""`, `teamSiteDomain` the
  tenant's SharePoint host, `manifestVersion "1.25"` (the app's).
- **Meeting Q&A** (app 5db56dd0, web.yammer.com/teamsmeeting): the runtime
  has `canParentManageNAATrustedOrigins: false` and
  `isDeeplyNestedAuthSupported: false`; context entityId "", the meeting
  chat and its meetingId, manifestVersion 1.16; NAA client 00bf137d for
  `https://web.yammer.com/teamsmeeting/user_impersonation`; many
  getContext calls. Without the meeting option it shows "Q&A is not
  available for this event."
- **Meeting Whiteboard** (app 95de633a): frameContext `meetingStage`,
  the same runtime as Q&A; getUser; NAA for whiteboard.microsoft.com,
  Graph and api.office.net; custom handlers sharepointSiteUrlAndDriveId,
  whiteboardUrlChanged, sendPassThroughData, updateBoardContentFromTeams;
  custom message `readyForUrl` (answered `[]`, then Teams posts
  `updateBoardContentFromTeams ["[]", ""]`), `changeWhiteboardUrl`,
  `loadingCallback`.

## Which apps get deeply nested NAA
- Teams' runtime answer's `isDeeplyNestedAuthSupported` and
  `canParentManageNAATrustedOrigins` are its NAA service's (module
  985817): `allowList.includes(appId)`, the list being ECS
  `extensibility.deeplyNestedAppAuthAllowList`. Measured: OneNote
  (`0d820ecd`) and Storyline true; Lists (`26bc2873`), Whiteboard, Q&A and
  Workflows false. OST reads the same ECS list (`api::app_host::deep_naa`)
  and falls back to the tab's own setting without ECS.

## Configuration pages and Save (Add a tab, measured 2026-11-16)
Choosing OneNote in OST group test's Add a tab:
- The dialog (600 x 603 in a 1212 x 700 window) frames the app's
  configurationUrl in an `hwc-iframe` titled `tab-configurable-content`
  (no id; `allow` `clipboard-write *; local-network-access *; autoplay;
  camera *; microphone *; encrypted-media *; speaker-selection *;`,
  the usual sandbox with `allow-downloads`), 550 x 412, 25 in and 94.5
  down. Placeholders the context has no value for stay as they are
  (`groupId={groupId}&channelType={channelType}` in a chat).
- The page (m365.cloud.microsoft/launch/onenote/officeunihost/config,
  TeamsJS 2.33): initialize (answered frameContext `settings`), getContext,
  setValidityState `[false]` several times, getChatMembers, registerHandler
  load / fullScreenChange / themeChange / save, appLoaded, success; picking
  a notebook sends setValidityState `[true]` (Save turns on).
- **Save**: Teams posts `{func: "settings.save", args: [{}]}`; the page
  calls `settings.setSettings [{entityId, websiteUrl, contentUrl,
  suggestedDisplayName, apiUrl, notebookSource}]` (answered `[true]`), then
  `settings.save.success []`. Teams then adds the tab (add-a-tab.md: the
  thread property, the post, the reply chain), closes the dialog, opens
  the new tab and frames its contentUrl (frameContext `content`).
- A content page may set its tab up later the same way (no save event):
  Lists' page after making the list, OneNote's ChannelNotes after
  provisioning; Teams rewrites the tab (add-a-tab.md), posts
  `beforeUnload` and, on `readyToUnload`, `load [{entityId, contentUrl}]`
  to its cached frame.

## Dialogs (task modules, measured 2026-11-16)
- Teams' dialog (`task-module-dialog`): the taskInfo's width (Workflows:
  900), radius 8, the dialog shadow, 27 above the header; the header
  (`taskModuleHeader`, 55.3 tall, padding 0 32): the app's 32 px icon
  (radius 28.56%, #FAFAFA) at (32, 38.7), the title (h1, 20/28.57 bold) at
  76, Close (`closeButton`, 32 x 55.3) at width − 64; the page
  (`iframe-container`) 90.3 down, the taskInfo's height (560), in an
  `hwc-iframe` titled after the app (`allow` `clipboard-write *;
  local-network-access *; autoplay`).
- The page runs with frameContext `task`, the runtime without deeply
  nested NAA, and a context with `dialogParameters: {}` (the Workflows
  dialog of a channel: `appSessionId` and `data-sessionid` the channel's
  id). Workflows asked NAA GetToken for client a0a3c1d3 (api.bap,
  service.flow, graph, api.powerplatform) and
  `copilot.eligibility.getEligibilityInfo`.
- An app opens one with `tasks.startTask` (dialog.url.open); Teams answers
  that request when it closes: `[null, result]` after the page's
  `tasks.completeTask [result]` (the result as JSON), or
  `["User cancelled/closed the task module.", undefined]` (platform-app,
  useTaskModuleResult). A taskInfo with a `card` is an Adaptive Card
  dialog; Microsoft's own apps may ask `useHeaderlessDialog`.
- **The workflow suggestion** (chat-app 139267): Teams'
  `launchTaskModule` with `appId 25b07509-bc6a-4a53-b683-9beb24e55570`,
  `templateName "Workflows"`, the Workflows icon, `taskInfo {width: 800,
  height: 600, url:
  automations.teams.cloud.microsoft/webapps/workflows/prod/suggestedAction/{findmeetingtime|createaplanner|remindme}?theme={theme}&locale={locale}&ringId={ringId}}`,
  the Workflows valid domains, and `launchContext {launchId, type 0,
  chatId, subEntityId: JSON.stringify(prefilledInputs)}`.

## Meeting Whiteboard: the meeting's board (measured 2026-11-16)
- Opening the tab, Teams asks the middle tier for the meeting's board
  (GraphQL getWhiteboardUrl): `GET {mt}/beta/meetings/fluidboard?threadId=
  {meeting chat}&messageId=0&organizerId=8:orgid:{organizer}&tenantId=…
  &meetingTitle=…` → `{url, shareUrl}`, `url` the board's address
  (`app.whiteboard.microsoft.com/meeting?embed=1&encodedShareLink=…
  &shareLinkId=…&meetingTitle=…` once the meeting has a board).
- The frame loads that address with `tabStartTime`, `correlationId`,
  `culture`, `enableReactApp=1`, `isInitiator`, `isEduUser=0`,
  `meetingId` (base64 of `0#{chat}#0`), `teamsEnvV2=prod`,
  `client=TeamsModern`, `userRole=Member`, `isEU=false`, `userId`,
  `userTenantId`, `isNAAEnabled=true` added (cacheable-iframe, title
  Whiteboard, 864 x 555 under the header).
- Whiteboard (TeamsJS 2.22): initialize (frameContext `meetingStage`),
  getContext (many), registerHandler sharepointSiteUrlAndDriveId /
  themeChange / whiteboardUrlChanged / sendPassThroughData /
  updateBoardContentFromTeams, getUser, NAA (client 95de633a:
  whiteboard.microsoft.com, Graph, api.office.net, the user's OneDrive,
  pushchannel.1drv.ms), `readyForUrl` (answered `[]`, then
  `updateBoardContentFromTeams ["[]", ""]`), then `changeWhiteboardUrl
  [url]` with the board's address (its `proofToken` included).
- Teams answers `[]` and keeps it for the meeting: `POST {mt}/beta/
  meetings/v2/whiteboard?threadId=…&messageId=0&organizerId=…&tenantId=…`,
  the body the address as a JSON string without the proof token, answered
  `{"success": true}` (twice in the capture). Everyone opening the tab
  then gets that board from fluidboard.
- `loadingCallback [success, error]`: Teams logs whether the board loaded
  (whiteboard-renderer `onLoadingCallback`) and answers `[]`.

## Meeting Q&A (scheduled meeting, measured 2026-11-16)
- "OST calendar test: created from OST" (a scheduled meeting) lists Q&A;
  its page (web.yammer.com, TeamsJS 2.49) sends initialize, getContext
  (several), NAA GetInitContext / GetToken (client 00bf137d), success,
  registerHandler themeChange, and shows "Q&A is not available for this
  event. Turn it on from meeting options. Learn more" (Q&A isn't turned
  on in that meeting's options).

## Personal apps from the app bar (measured 2026-11-16, TASK-0038)
Teams on the web as ost-test1 in OST's web profile (spatest), opened from
View more apps. Each app's personal tab (its definition's `staticTabs`) is
framed in the same host as tabs: `cacheable-iframe:<app id>`, hwc-iframe,
the usual sandbox with `allow-downloads`, `allow` `clipboard-write *;
media-playback-while-not-visible 'none'; local-network-access *;`
(Copilot adds `display-capture *;`), filling the area right of the app
bar (68, 84 in a 1212 x 700 window under the 36 px notification banner).
The context is the personal one: `entityId` the tab's, `subEntityId ""`,
`chatId ""`, `channelId ""`, `meetingId ""`, `teamSiteDomain` the
tenant's SharePoint host, `teamSiteUrl/Path/Id ""`, frameContext
`content`; `isFullScreen` from the app (manifest `isFullScreen`).

| app | id | frame (Teams on the web) | header | entityId | NAA client · scopes | other TeamsJS |
|---|---|---|---|---|---|---|
| Whiteboard | 95de633a-083e-42f5-b444-a4295d8e9314 | `https://whiteboard.cloud.microsoft/?embed=1&isOpenInPersonalApp=1` | Teams' app header (61 tall: tile, name, ···), frame 1144 x 555 at (68, 145) | the app id | 95de633a: whiteboard.microsoft.com, Graph, api.office.net, the user's OneDrive, clients.config.office.net | registerHandler sharepointSiteUrlAndDriveId / themeChange, getUser, many getContext, `loadingCallback [true]` |
| Shifts | 42f6c1da-a241-483a-a3cc-4f5be9185951 | `https://flw.teams.cloud.microsoft/shifts-web-app?ui-culture={locale}&tid={tid}&userObjectId={userObjectId}&sessionId={sessionId}&theme={theme}&ringId={ringId}&subEntityId={subEntityId}` (filled) | none (full screen), 1144 x 616 at (68, 84) | `shifts` | aa580612-c342-4ace-9055-8edee43ccb89: api.manage.staffhub.office.com, Graph | `getUserJoinedTeams [null]` → `[{userJoinedTeams: [{teamId, teamName, groupId, isTeamLocked, isTeamArchived, teamDescription, thumbnailUri, userTeamRole, teamType}]}]` |
| Clipchamp | com.microsoftstream.embed.skypeteamstab | `https://www.microsoft365.com/embed/launch/stream?auth=2&embedhost=StreamTeamsApp-PersonalTab` | none (full screen) | `embedwatchlist` | 4765445b-32c6-49b0-83e6-1d93765276ca: its own api, Graph, substrate, SharePoint, 4345a7b9, 394866fc | registerHandler themeChange / focusEnter / backButton |
| Copilot | b5abf2ae-c16b-4310-8f8a-d3bcdb52f162 | below | none (full screen) | `entity1-d870f6cd-…` | c0ab8ce9-e9a0-42e7-b064-33d422df41f1 (deeply nested NAA on) | below |

The runtime answered `canParentManageNAATrustedOrigins` /
`isDeeplyNestedAuthSupported` false for Whiteboard, Shifts and Clipchamp
and true for Copilot and the Office apps (Teams' ECS allow list).

**Events** isn't a hosted page: Teams draws it itself (Discover and Manage
tabs, `one-events-discover-tab` / `one-events-manage-tab`; "Introducing an
app for all things events!" with View meetings / View audio recaps; "No
events have been scheduled yet" and Create event; Manage: Connect apps,
"Get started with a template"; Pin app, Filters, Create event) from the
virtual events service, `GET https://teams.microsoft.com/api/virtualevents/
prod/beta/eventOverviews?pageSize=…&sortBy=…&sortOrder=…&startTo|startFrom|
endFrom|endTo=…&returnRequesterProperties=…&eventStatus=…&includeRequesterStatus=…`
with Teams' own token for resource 7fc21101-d09b-4343-8eb3-21187e0431a4
(Manage counts Drafts / Published / Past with `manageFilterType`,
`eventTypes` Townhall, Webinar). OST draws it natively (TASK-0209):
docs/spec/events.md.

## Copilot (the chat list's row, measured 2026-11-16)
- The row: `list-item-metaos-copilot` (`OneGQL_BizChatMetaOSConversation|
  b5abf2ae…`), 248 x 32 at the list's top above Quick views; clicking it
  records `PUT {mt}/beta/me/engagementSurfaces/actions {"items":
  [{"action": "NavigateToBizChatSimpleCollab"}]}` and opens the Copilot
  app's page beside the list (864 x 616 at 348, 84; no header).
- **Server-side rendering**: the frame is named
  `embedded-page-container_<uuid>` and has no src; Teams posts a hidden
  form into it (`method=post`, `target` the frame's name; Teams'
  submitSSRForm) to the tab's address,
  `https://m365copilotapp.svc.cloud.microsoft/chat?OID={user}@{tenant}&hostApp=hub&isanonymous=true&culture={locale}&mysite={mySiteDomain}&hostName=TeamsModern&hostClientType={hostClientType}&sessionId=…&renderingSurface=%7Bpage.renderingSurface%7D&theme={theme}&hostRing={ringId}&parentSessionId={sessionId}`,
  with fields `cv-id` (a correlation id), `Authorization` (the raw access
  token, no "Bearer": brokered for client c0ab8ce9 and
  `https://m365copilotapp.svc.cloud.microsoft/.default`, redirect
  `brk-multihub://m365copilotapp.svc.cloud.microsoft`) and `hostContext`
  `{clientPlatform, hostName, locale, theme, appSessionId, userClickTime,
  hostSessionId, subPageId}` (`trustedSharePointOrigins` when known).
- Context: `hostFeatures.serverSideRendering true`, `isFullScreen true`,
  `manifestVersion 1.23`, `mySiteDomain` / `mySitePath` (your OneDrive),
  `subEntityId` `{"hostSettings":{"enableDeeplinks":"true","focusOnLoad":
  "Compose"},"launchOptionPayload":"<base64 of {"id":"","scenario":
  "Default","chatType":"","properties":{},"version":1,"referral":
  {"cmmid":"cmmnxawun8n"},"callerInfo":{"scope":"None","entryPoint":
  "SimpleCollabList"},"serverVariants":[]}>"}`.
- TeamsJS: initialize (its valid origins), getContext, registerHandler
  beforeUnload / load / contextualChatChanged / updatePromptInputData /
  updateDataContext / copilotSearchSidePaneVisibilityChanged /
  updateCapabilities / reloadConversation / edgeStopAction /
  onAppFirstForeground / onAppForeground / themeChange / search.executeSearch
  / navigate.module / focusEnter / shortcutRelay.hostShortcutChanged,
  `ChatReady [{renderMode: "SSR"}]`, success, NAA (Graph, m365.cloud.microsoft,
  ic3, substrate sydney and search, loki, titles.prod.mos, arc.msn.com,
  bb893c22), `shortcutRelay.getHostShortcuts`, `executeDeepLink
  ["https://teams.microsoft.com/l/copilot/notify?bold=false"]` (answered
  `[true]`).

## Share to Outlook (measured 2026-11-16)
- A chat message's ··· ▸ Share to Outlook (`message-share-to-outlook`):
  Teams opens its task module for the Outlook app (40517485-2262-4135-b174-
  401da4aa6f0f, appName "Outlook", icon `statics.teams.cdn.office.net/
  evergreen-assets/apps/outlook_largeimage.png`, title "Share conversation
  over email", width 800, height large) in a loading state, then asks the
  middle tier for a draft of the conversation in your mailbox: `GET
  {mt}/beta/shareToOutlook/GetEmailIdForConversation?threadId={chat, as
  is}&messageId={id}&locale=en-us[&bodyType=SingleMessage]` (GraphQL
  generateEmailIdForConversation) → the draft's Exchange id.
- The page: `https://outlook.office.com/mail/opxdeeplink/compose/{emailId}?isAnonymous=true&opxAuth=true&hostApp=teams&useOwaTheme=true&culture=en-us`
  (ECS shareToOutlookOPXBaseUrl / shareToOutlookOPXConfig), framed in an
  hwc-iframe titled "Share conversation" (`allow` `clipboard-write *;
  local-network-access *; autoplay`), 800 x 462 at (206, 153) with the
  dialog 800 x 529 at (206, 86) in a 1212 x 700 window. Header: the 32 px
  icon at (32, 27), "Outlook" over "Share conversation over email", Close
  64 from the right. Outlook's compose shows To / Cc, the subject "<chat>:
  chat conversation from Microsoft Teams" and the conversation card.
- TeamsJS from the page: initialize (frameContext `task`),
  `authentication.getAuthToken [["https://outlook.office.com/"], null, null,
  null]` twice (answered `[true, <token>]`), getContext, appLoaded,
  success.
- Closing without sending: Teams discards the draft, `DELETE
  {mt}/v1/shareToOutlook/email?emailId={id}` (deleteShareToOutlookEmailDraft).
- In the menu it followed Mark as unread (it moved above it once used:
  Teams orders some items by use).

## Immersive Reader (measured 2026-11-16)
- A chat message's ··· ▸ More actions ▸ Immersive Reader
  (`message-actions-immersive-reader`; More actions also lists apps'
  actions: Create a Polly, Create Planner task, Create workflows).
- Teams gets its own token for `https://immersivereader.cloud.microsoft/.default`
  (client 5e3ce6c0, GraphQL immersiveReaderAuthToken) and runs Microsoft's
  Immersive Reader SDK 0.8.0 in its own window: a `div` `position: fixed;
  width: 100vw; height: 100vh; left: 0; top: 0; border-width: 0;
  perspective: 1px; z-index: 1000; background: white; overflow: hidden`
  holding an iframe titled "Immersive Reader Frame" (`allow="autoplay;
  microphone"`, `aria-modal`, `allowfullscreen`, `position: static; width:
  100%; height: 100%`) at
  `https://learningtools.onenote.com/learningtoolsapp/cognitive/reader?exitCallback=ImmersiveReader-Exit&sdkPlatform=js&sdkVersion=0.8.0&cookiePolicy=disable&cognitiveAppId=Teams`.
- The reader posts the string `ImmersiveReader-ReadyForContent` (and
  `readyForStorageId`, unanswered); Teams posts
  `JSON.stringify({messageType: "Content", messageValue: {cogSvcsAccessToken,
  request: {chunks: [{content: "<sender> <M/d/yyyy> <h:mm:ss AM> <br/>",
  mimeType: "text/html"}, {content: <the message's HTML, cards as text>,
  mimeType: "text/html"}]}, launchToPostMessageSentDurationInMs,
  sendPreferences: false, internalSdkUseAADBearerTokenForGcmCall: true}})`.
  The message's HTML is its raw content with each card's placeholder
  (`<span itemid="…</span></span>`, a media card's `<URIObject
  type="SWIFT.1" …</URIObject>`) replaced by `<br> {card text} <br>`
  (Teams' module 299105). The card text is Teams' accessible text for it
  (module 498891): an Adaptive Card's `speak`; a hero, thumbnail or
  sign-in card's "Card title:\n{title}. \n\n", "Card subtitle:",
  "Card text content:" (HTML stripped), "Image {i}:\n\n" per picture
  (from 0) and per button "Button {n}:", "Button title:", "Button value:"
  (openUrl); an Office 365 connector card's title, text and per section
  "Section {n}:", its title, text and activity title, subtitle and text.
  Measured on a thumbnail (link) card: `<p>OST TEST 168a app card …</p>
  \r\n<br> Card title:\nRust (programming language). \n\nCard text
  content:\nRust is a general-purpose … programming. \n\nImage
  0:\n\n <br>`. OST: `api::reader_text`, the message's `reader_html`.
  The reader answers `ImmersiveReader-SessionId:…`, `readyToPlay`,
  `ImmersiveReader-LaunchResponse:{"success":true,…}`,
  `ImmersiveReader-LaunchSuccessful`, and calls
  immersivereader.edu.svc.cloud.microsoft itself. Its back arrow posts
  `ImmersiveReader-Exit`; Teams removes the layer.

## Office files in Teams (measured 2026-11-16)
- With "Teams" chosen (Settings ▸ Files and links; OneDrive's Open ▾
  says "Edit in Teams"), a Word file opened from the OneDrive app opened
  in the Word app's page, which joined the app bar (its icon under
  Copilot) and filled the area right of it, full screen: app
  `d7958adf-f419-46fa-941b-1b946497ef84` (Word; Excel
  `1c256a65-83a6-4b5c-9ccf-78f8afb6f1e8`, PowerPoint
  `3e0a4fec-499b-4138-8e7c-71a9d88a62ed`, Teams' file-type map),
  `https://m365.cloud.microsoft/launch/word/officeunihost/teams?auth=2&flight=officeunihost&source=TEAMS-WEB.teamsSdk_<the opening app>_ns.rwc.content&appSessionId=…`.
- Context: `entityId "MyNotebook"`, `isFullScreen true`, `subEntityId`
  `{"title", "fileId" (the item's unique id), "objectUrl" (its WebDAV
  address), "siteUrl", "serviceName": "teamsSdk_<opening app>_ns",
  "fileType", "shareId": "", "shareUrl": "", "subEntityId" (the folder's
  view params), "context": "bim", "ctx": "rwc", "viewerAction": "edit",
  "atpSharepointData": null, "baseUrl"}`.
- TeamsJS: initialize, getContext, NAA GetInitContext / GetTokenPopup
  (client fd5f78f6, the OneDrive site), getUser, registerHandler log.request
  / load / beforeUnload / themeChange / focusEnter, appLoaded, success,
  `manageNAATrustedOrigins ADD ["https://oauth.officeapps.live.com"]`; the
  page frames Word for the web (`usc-word-edit.officeapps.live.com/we/
  wordeditorframe.aspx?…&uih=teams&uiembed=1&…&to=https%3A%2F%2Fteams.cloud.microsoft&dnaa=1…`),
  whose OAuth frame asks NAA for 243c63a3 through Teams.
- The Office page's own Close (top right of Word's ribbon row) returns to
  where the file was opened (the OneDrive app) and the app leaves the app
  bar: Word posts its own `UI_Close`, the page sends TeamsJS `navigateBack
  []`, Teams answers `[true]`, posts `beforeUnload` and, on
  `readyToUnload`, goes back.
- Settings: Teams on the web offers Teams and Browser (synced
  `fileOpenPreference` teamsV2 / web); Teams desktop adds Desktop app with
  Office installed (file-actions.md).

## Meeting Notes (in the call window; measured 2026-11-16, TASK-0209)
- The call's Notes (`MeetingDetailsButton`, "Open notes" / "Close notes")
  opens the side panel `calling-right-side-panel` "Meeting notes" (360
  wide, #F5F5F5): a white header 58 tall ("Notes" 18/25.7 bold #252423 22
  in; More actions and Close 32 x 32, 16 from the right) and, 16 under it,
  the notes as a Loop page (Loop's page container in a sourceless frame,
  359 x 523 in a 752 tall window; the meeting blueprint: Agenda "Topic,
  @name, time allotted", Meeting notes "Add meeting notes", Follow-up
  tasks "Add task"). More actions: Shared locations, Copy component, See
  who has access, Open in Loop, Add to Loop workspace.
- Where the page comes from (Teams' modules 648378 call-meeting-notes,
  600612 its helper, 559325 CollabNotesContext, services-io-collab-object;
  measured on a solo Meet now in Teams on the web):
  - the call's meeting state `collabResources.notes` `{value: {type:
    "notes", resourceUri}, sequenceNumber}`, when someone made them;
  - Teams' meeting-notes service: `POST https://teams.microsoft.com/api/
    mcps/prod/notes/getOrCreateMeetingNotes` (ECS
    `cmdMeetingNotesServiceEndpoint`, resource `cmdMeetingArtifactsServiceResource`
    6bc3b958-689b-49f5-9006-36d165f30e00) with `{threadId, organizer
    ("<oid>@<tid>"), meetingTitle, messageId "0", meetingUrl,
    externalEntityKey (iCalUid), seriesExternalEntityKey, locale}` →
    `{resources: [{type: "notes", location, resourceState
    (committed / pending)}], expiry}`; pending is asked again up to three
    times after the expiry (5 s default, 30 s at most). Teams calls it when
    its Copilot bot pings the call (`copilotBotPing`) and from the meeting
    chat's notes (`getOrCreateMeetingNotesViaService`); scheduled meetings
    also use the collab object service (`…/mcps/prod/collab`
    readandoptionallyreserve / commitresource);
  - otherwise, as Teams on the web did for the Meet now:
    `updateMeetingStates {"collabLeaders.notes": {"value": {"type":
    "notes"}, "sequenceNumber": 1}}`, `GET graph me/drive/special/meetings`,
    the page made by Fluid (`POST {onedrive}/_api/v2.1/drives/{d}/items/
    root:/Meetings/<meeting title>.loop:/opStream/snapshots/snapshot`, no
    share link scope; Loop's `blueprintId: "meeting"`), `POST …/items/{i}/
    createLink {"type": "edit", "scope": "organization"}`, then
    `updateMeetingStates {"collabResources.notes": {"value": {"type":
    "notes", "resourceUri": "<the link>?nav=…"}, "sequenceNumber": 1}}`.
- OST (`MeetingNotesPane.qml`, `api::meeting_notes`,
  `calling::meeting_notes`, `--call-notes-test`) does the same in that
  order and shows the page in its Loop host (kind `meetingNotes`).
- The service wants the meeting's iCalUid for a scheduled meeting (400
  `InvalidNotesCreationRequest` "Missing externalEntityKey or
  seriesExternalEntityKey for scheduled meeting" without it); a call
  joined by its link has none in the join response, so OST takes it, the
  organizer and the subject from the meeting chat's thread properties.
  A scheduled meeting refuses the leader claim (`updateMeetingStates`
  400, subCode 6169 "This meeting does not support electing collab
  leader"): Teams makes those notes through the collab object service
  instead (not traced; OST doesn't).
- Live (OST on linuxlt, 2026-11-16, a solo scheduled meeting of
  ost-test1's with nobody invited): Notes → the service answered with the
  notes' link at once (committed); Loop's page container framed, loaded,
  rendered and connected in the Notes panel ("Just start typing…", the
  insert row). The meeting and its notes file were deleted afterwards.

## Video apps (Avatars, TASK-0140)
- Teams desktop gives video apps WebView2's texture streams (runtime
  `supports.video.mediaStream`): the app sends
  `video.mediaStream.registerForVideoFrame [config]`, Teams posts
  `video.startVideoExtensibilityVideoStream [{streamId, metadataInTexture}]`,
  and the app reads `chrome.webview.getTextureStream(streamId)` and
  registers its output with `registerTextureStream(streamId, track)`.
- OST's host does the same with `cfg.video` (`{socket, appOrigin}`):
  `video_app_frame.js` (in the app's frames of that origin under the host
  page, their own world, from document creation) implements
  `chrome.webview` with MediaStreamTrackGenerator /
  MediaStreamTrackProcessor; the frames cross between the host page and
  the app frame by postMessage (transferred buffers) and between the host
  page and OST over a localhost WebSocket with a secret path
  (`desktop/src/avatars.rs`). Other video funcs: `registerForVideoEffect`,
  `personalizedEffectsChanged`, `videoEffectChanged`,
  `videoEffectReadiness`, `notifyError`, `performance.*` (events to QML);
  Teams' events `video.effectParameterChange`,
  `video.mediaStream.audioInferenceDiscardStatusChange` and
  `meeting.meetingReactionReceived` go through `sendFrameMessage`.
- Live (2026-11-17, ost-test1 on linuxlt): the Avatars renderer signed in
  by NAA, listed the account's avatar and 70 backgrounds, applied the
  avatar, registered for frames with its 153 kB viseme model and drew
  640 x 360 frames; its `uiOnly` side panel and its builder (personal tab
  "Customize Avatar") ran in the host as in Teams.

## OST's host (why this design)
Options weighed:
- **Inject a native interface into a top-level page** (TeamsJS'
  "frameless" mode, `window.nativeInterface` / `onNativeMessage`, as Teams
  mobile does): the app would be the top window, so the deeper frames'
  NAA bridge (posting to `window.top` with Teams' origin as target, and
  accepting only Teams' origin) would talk to the app instead of the host,
  TeamsJS wouldn't polyfill the bridge, and the page would run in a mode
  Teams desktop never uses. Rejected.
- **A host page OST serves under its own scheme** (ost://): the pages'
  frame-ancestors, TeamsJS's valid origins and the nested bridges' target
  origin all require a Teams origin. Rejected.
- **Chosen: Teams' own arrangement.** OST loads a small host page into the
  web view with Teams' origin (`loadHtml(…, "https://teams.cloud.microsoft/")`,
  Chromium's load-data-with-base-URL: the document gets that origin, and
  nothing is fetched from Teams), frames the app in it with Teams'
  hwc-iframe attributes, and answers by postMessage exactly as captured.
  The host script runs in an isolated JavaScript world of that page
  (ApplicationWorld), so neither the page's main world nor the app's
  frames can reach it or its web channel to OST. Tokens come from OST's
  Rust side: NAA from `auth::broker` (Teams' broker request, see above,
  cached in memory until 5 minutes before expiry), getAuthToken from the
  stored sign-in; they pass through the channel and postMessage only and
  are never logged.

## OST status (live checks 2026-11-16, ost-test1 on linuxlt)
- [x] Channel Notes (OST Test Team › General): OneNote's editor in the
  host, typed into and undone; Reload, Expand, Open tab in new window and
  App permissions (`--app-host-test`).
- [x] Notes provisioning (OST test channel 2, first opening): OneNote's
  wait page ("We're almost there! Please stay on this page."), its
  section and page made, the tab saved as Teams saves it, then the
  notebook. The first attempt sat on the wait page for over a minute
  (the section had just been deleted by the test reset); after Reload it
  completed in seconds.
- [x] Storyline; Meeting Whiteboard on the meeting's own board
  (fluidboard, changeWhiteboardUrl kept, loadingCallback answered);
  Q&A in a scheduled meeting chat as Teams shows it there.
- [x] Configuration pages and Save (OneNote in OST group test); Lists'
  content page setting its tab up (OST test channel); getChatMembers.
- [x] Dialogs: the channel's Workflows dialog runs as Teams' task module
  (frameContext task) and shows Workflows' page as in Teams.
- [ ] The workflow suggestion's dialog opens as Teams launches it (800 x
  600, Teams' address and launch context), and the page initializes and
  reports success, but stays blank in OST: it logs "Initial app state
  does not contain valid QSP" and "User ID or Tenant ID is empty" — Teams'
  Workflows task-module runtime (workflowsRuntimeConfig) adds more than
  the template address, not traced yet; the tenant has suggestions off,
  so Teams' own rendering couldn't be compared.
- [ ] App-initiated dialogs (tasks.startTask from a tab) are wired
  (dialog, completeTask / cancel answers, messageForParent/Child,
  updateTask) but no tested app opened one; Adaptive Card dialogs and
  header-less dialogs aren't drawn.
- Shortcuts: `shortcutRelay.getHostShortcuts` answered.
- TASK-0038 (live 2026-11-16, ost-test1 spatest profile on linuxlt,
  `--embedded-apps-test`):
  - [x] Whiteboard (Teams' app header, your boards, signed in), Shifts
    ("Welcome to Shifts", full screen) and Clipchamp (full screen) from
    the app bar: each app's personal tab from its definition in the host
    (initialize, appLoaded, success; Whiteboard's loadingCallback).
  - [x] Office for the web: ost-open-test.docx opened with the "Teams"
    choice in Word's page (`launch/word/officeunihost/teams` with Teams'
    `source` and `appSessionId`), the document shown and editable,
    signed in; Settings ▸ Files and links offers Teams and Browser (no
    desktop Office app on linuxlt).
  - [x] Share to Outlook on a message in OST group test: the middle tier's
    draft, Outlook's compose in Teams' dialog with the conversation card,
    closed without sending, draft discarded.
  - [x] Immersive Reader on the same message: the reader launched
    (LaunchResponse success) with the sender, date and message, and closed.
  - [x] Copilot from the chat list's row: the server-rendered page
    posted with the brokered token, "Hi, what can I help you with?" and
    the compose box as in Teams (initialize, success; ChatReady and the
    notify deep link answered as Teams does).
  - [x] Word's Close (navigateBack) returns to the OneDrive app and the
    app leaves the app bar.
  - [x] A channel's Loop page tab (OST Test Team › General › Page, "Loop
    paragraph") opens signed in in OST's Loop host (framed, code,
    rendered, connected), with Teams' header and insert row
    (`--loop-test=page --loop-tab=Page`).
  - [x] Events: drawn natively (TASK-0209, docs/spec/events.md).
  - [x] Meeting Notes in the call window (TASK-0209, above).
  - [x] Immersive Reader with cards (TASK-0209, below).

Host features:
- [x] The host: the frame as Teams', initialize / getContext /
  getUser / registerHandler / appLoaded / success / failure /
  readyToUnload, NAA (GetInitContext, GetToken, GetTokenPopup) from the
  app and from nested frames, manageNAATrustedOrigins, setSettings
  (content: saved as Teams does, then beforeUnload / load; settings
  pages: kept for the dialog), getSettings, setValidityState,
  executeDeepLink, themeChange.
- [ ] authentication.getAuthToken: answered from the stored sign-in for
  the app's webApplicationInfo resource; not seen in a capture yet.
- [x] settings.save round trip, getChatMembers, copilot eligibility,
  tasks.startTask / completeTask / updateTask, messageForParent /
  messageForChild, Whiteboard's readyForUrl / loadingCallback /
  changeWhiteboardUrl; deeply nested NAA per Teams' ECS allow list.
- [ ] authentication.authenticate (pop-up sign-in windows the host
  parents), stageView, people, files and the other capabilities the
  runtime lists: not handled yet (logged by name).
