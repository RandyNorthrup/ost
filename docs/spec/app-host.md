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
  `{channelName}`, `{teamType}`.

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
- [x] Storyline; Meeting Whiteboard (opens a new board, see below).
- [ ] Meeting Whiteboard's changeWhiteboardUrl / loadingCallback; Q&A
  untried (no scheduled test meeting).
- [ ] Another app's configuration page (OneNote's, in OST group test):
  hosted, it initializes, reports validity and succeeds; it also asks
  `getChatMembers` (not handled); Save not built.
- Shortcuts: `shortcutRelay.getHostShortcuts` answered; the readyForUrl
  answer for Whiteboard.

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
- [ ] authentication.authenticate (pop-up sign-in windows the host
  parents), dialogs (`tasks.startTask`), stageView, people, files and the
  other capabilities the runtime lists: not handled yet (logged by name).
