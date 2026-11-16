# How Teams hosts a Loop page (a chat's Notes, a channel's Page) — spec

Measured in Teams on the web (teams.cloud.microsoft, build 1415/26110100710)
as ost-test1 on 2026-11-16, inside OST's own web profile on linuxlt, over
its DevTools port: the Loop frame's scripts and requests, every provider
Loop's page container asked the host for (a tracing hook on the
container's dependency synthesizer: names and shapes only, no values that
could be secrets), the token requests' non-secret parameters, and Teams'
own host code read from its bundles (chat-app 600116 scope builder, 808482
load/create, 163214 render, 436488 render options, 627924 storage policy,
347827 / 439940 settings, 244729-131941 ECS client; OfficeWebHost chunks
285723 / 595515 / 600862). Pages used: OST group test's Notes; a New page
in OST Test Team › OST test channel.
OST: `desktop/src/loop_host.js`, `desktop/src/loop_bridge.js`,
`LoopPage.qml`, `ChatNotesTab.qml`, `ChannelPageTab.qml`,
`api::loop_page`, `api::tab_add::{add_new_page_tab, set_page_component_url}`,
`desktop/vendor/fluid-loader/`, `--loop-test`.

## The frame
- Teams' OfficeWebHost makes a "sourceless iframe V2" in the tab under
  Teams' own header: `<iframe frameborder="0" tabindex="-1" title="">`,
  `height: 100%; width: 100%` (layout `fixedByHost`), its `srcdoc`
  `<!DOCTYPE html><html><head><meta charset="utf-8" /><link rel="preconnect"
  href="https://res.cdn.office.net" crossorigin></head><body style="margin:
  0px;"><div id="componentDiv"></div></body></html>`. Same origin as Teams;
  the component div is `position: absolute; inset 0` and the frame's
  document `overflow: hidden`.
- Into that frame Teams loads, with `<script crossorigin="anonymous"
  async=false fetchpriority=high>` (three tries):
  - the ODSP driver: `res.cdn.office.net/fluid/prod/odsp-driver/versionless/
    deploymentManifestOdspDriver.json` → `{jsBaseUrl, v1: {index}}` →
    `…/hashed/index.*.js`, global `FluidOdspDriver` (Teams sets
    `FluidOdspDriver = {scriptLoadingStarted: true}` first); later its
    `socketModule.*.js`;
  - the page container: `loop-page-container/versionless/
    loopPageContainerCodeLoadDetails.json` →
    `fluidCodeDetailsOverride.package` (`@fluidx/loop-page-container`,
    version e.g. 20261109117, `fluid.browser.umd.files`: runtime, griffel css,
    loopPageContainer js and css; `library: "loopPageContainer"`); the
    container then loads its own chunks and `strings.en-us` from the same
    CDN folder.
- The Fluid loader itself runs in Teams' page (Teams bundles
  `@fluidframework/container-loader` 2.118.1), so the container's objects
  pass between the two windows.

## The loader (OfficeWebHost)
- `new Loader({urlResolver, documentServiceFactory, codeLoader, scope:
  {IFluidDependencySynthesizer}, options, logger, configProvider})`.
- `documentServiceFactory`: `FluidOdspDriver.getDocumentServiceFactory(
  {tokenProvider, logger, driverCache, hostStoragePolicy,
  settingsProvider})`; `hostStoragePolicy` `{enableRedeemFallback: true,
  enableSingleRequestForShareLinkWithCreate:
  composeSingleRequestForShareLinkEnabled}` (+ `snapshotOptions: {mds:
  sizeLimitValueBytes}` when `sizeLimitEnabled`).
- `urlResolver`: ODSP's `OdspDriverUrlResolverForShareLink` (app name
  "Teams", `shareLinkFetcherProps {tokenFetcher, identityType:
  "Enterprise"}`); it reads the link's `nav` (base64 of
  `s=<site path>&d=<drive>&f=<item>&c=%2F&fluid=1&a=Teams&p=%40fluidx%2Floop-page-container`)
  and fetches the share link (`{site}/_api/v2.0/drives/{d}/items/{f}?select=webUrl,webDavUrl,sharepointIds`).
- `codeLoader`: Teams' SimpleCodeLoader: the package from the code load
  details (only files on the CDN allow list), its library global from the
  frame; a library with `fluidExport.ConfigurableRuntimeFactory` is
  wrapped so `instantiateRuntime` first calls `configure(codeDetails.config)`
  (a New page's config: `{blueprintId: "paragraph"}`). Version compare: the
  package version as a number, `0.0.1` lowest.
- **Existing page**: `loader.resolve({url: <the page link>, headers:
  {isSharingLinkToRedeem: oneWayRedeemEnabled, isRedemptionNonDurable,
  "X-CLP-Compliant-App": ipEnabled, loadMode: {opsBeforeReturn: "cached",
  deltaConnection: "none"}}})` (the container starts paused,
  `startContainerInPausedState`), then `getEntryPoint()` (or its
  `UrlRouterFetcher` for a data-store path other than "/"), then
  `container.connect()`.
- **New page**: `createDetachedContainer({package: {name:
  "@fluidx/loop-page-container", version: "0.0.1", fluid: {browser: {umd:
  {files: [], library: ""}}}}, config: {blueprintId: "paragraph"}})`, drawn
  at once, then `container.attach(createOdspCreateContainerRequest(siteUrl,
  driveId, "<channel folder>", "Loop paragraph.loop", {scope: "default",
  role: "edit"}))` about two seconds later (`LoopComponentUrl.
  initializeLoopComponentUrl`; the name is Teams' "Loop paragraph",
  `fluid_compose_LiveParagraph`). The request:
  `POST https://<tenant>.sharepoint.com/_api/v2.1/drives/{team drive}/items/root:/%2FOST%20test%20channel/Loop%20paragraph.loop:/opStream/snapshots/snapshot?createLinkScope=default&createLinkRole=edit`.
  The page's link is then `container.getAbsoluteUrl("/")`: the share link
  (`https://<tenant>.sharepoint.com/:fl:/r/sites/<team>/Shared%20Documents/<channel>/Loop%20paragraph.loop?d=w…&csf=1&web=1`)
  plus `&nav=` as above.
- **Rendering** (163214): `component.ComponentInitializer?.initialize()`,
  `(await component.HTMLViewable.getView()).HTMLView.render(componentDiv,
  options)`; the options (436488) from the page's fluid settings'
  `viewProperties`: `{compactMargins (default true), onlyInlineComponents
  (enableOnlyInlineComponents, default true), maxHeight,
  narrowVisualSpacingLeft/Right, mediumVisualSpacingLeft/Right,
  visualSpacingTop (0), visualSpacingBottom: 0, layoutMode, maxContentWidth,
  visualSpacingLeft: 0, visualSpacingRight: 0}`.

## The host's services (the dependency synthesizer)
Every provider Loop asks for is optional. Teams registers (600116):
- `TokenProvider`: `{identityType: "Enterprise", getToken(scopes,
  {claims, forceRefresh, siteUrl, driveId, itemId, request, tenantId})}` →
  `{token}`. Asked (page and driver): `https://<tenant>.sharepoint.com/files.readwrite.all`,
  `https://pushchannel.1drv.ms/pushchannel.readwrite.all`,
  `https://augloop.office.com/v2/.default`, `user.read` (Graph
  licenseDetails), `Organization.Read.All`, `https://substrate.office.com/Files.ReadWrite.Shared`
  (the WorkingSetFiles recent-files mark). Teams answers with its own web
  client's tokens (client 5e3ce6c0, `redirect_uri
  https://teams.cloud.microsoft/v2/authv2`, scope `<resource>/.default
  openid profile offline_access`).
- `SettingsProvider`: Loop's ECS settings: `GET https://ecs.office.com/
  config/v1/Fluid/0.0.0.1?agents=FluidExperiences,Segmentation&audience=
  <fluidAudience>&userId=<oid>&tenantId=<tid>&hostName=<Microsoft Teams Web |
  Microsoft Teams Maglev (desktop)>` (no auth); `getSetting(name, default,
  namespace)` = the reply's `[namespace][name]` ("on"/"off" as booleans) or
  the default; `getLiveSetting` waits for the reply; `audience`. Teams'
  overrides: `paragraphWithoutInsertionMenuExperimentEnabled` and
  `scriptor.isDiscoveryFooterEnabledInDetachedStateOnly` from its fluid
  settings, `ActivityTransport.Pipelines.Common.Mention` 2,
  `context.tenantId`; for pages `loopPageContainer.renderHeaderByDefault`
  true (Loop draws the page title); chat notes: `atMentions.*` client-lie
  switches (off once attached).
- `UserContext {user: {tenantId, id: <oid>, userIdSpace: "UserObjectId"}}`,
  `InternationalizationContext {uiLocale: "en-us"}`, `TelemetryConfig
  {hostCorrelationId, hostSessionId, scenarioStartTime,
  disallowServiceTelemetry: false, hostAppName: "Teams",
  hostScenarioLifecycle: "Load" | "Create"}`.
- `OfficePolicyProvider {isConnectedExperienceEnabled, getPolicy(p)}`:
  `{value: "0"}` except `undefined` for `L_Loop` policies in a chat thread
  when Teams' enableDefaultPolicyValue / allowFluidCollaborate /
  enableFluidThread are on.
- `HostViewProperties {getViewProperties() → {viewType}}` (Small for
  notes, Large otherwise), `StylingProvider` (theme properties, among them
  `--ms-themeColorThemeName` "default"; `on`/`removeListener`
  `themePropertiesChanged`, `textStylesChanged`), `ResolvedUrlProvider
  {getResolvedUrl()}`, `FluidUrlResolverProvider {urlResolver}`,
  `FluidDocumentServiceFactoryProvider {documentServiceFactory,
  getCreateDocumentRequest(fileName)}`, `NamespaceLogger` (Teams' telemetry;
  `PersistedProperties.getPersistedProperties()` → hostCorrelationId,
  hostScenarioName `Load_Page_Chat` / `Create_Page_ChannelTab`, hostName,
  loopAudience, hostSessionId, hostAppVersion, hostAppPlatform),
  `LoopTrustedTypesPolicy`, `LoopTelemetrySink`, `PresenceColorProvider`,
  `MenuItemProviderService` (people suggestions for @), `PeopleService`,
  `NotificationService`, `CommandingSurfaceTreeViewProvider`,
  `NestedLoopComponentHosting`, `ComponentDialogProvider`, `Copilot`.
- Asked but not given by Teams: Theming, DOMDependency, PageCreationProvider,
  SelectionService, ShareService (chat notes), AugLoopRuntimeProvider, …

## Teams' fluid settings
The page's settings category's `fluid` (`fluidThread` for chat notes,
`channelPages` for a channel's Page: Teams' built-in defaults from its
config bundle, overlaid key by key by ECS) laid over ECS's
`messaging.fluid`, key by key, so the category's `viewProperties` replace
messaging's. Chat notes: `viewProperties {compactMargins: false,
layoutMode: fixedByHost, narrowVisualSpacingLeft/Right: 28, viewType:
Small, visualSpacingTop: 12}`, `ipEnabled`, `oneWayRedeemEnabled`; a
channel's Page the same with viewType Large and a 10 MB size limit
(`sizeLimitEnabled` from ECS). Measured render options of a channel's
Page: `{compactMargins: false, onlyInlineComponents: false,
narrowVisualSpacingLeft: 28, narrowVisualSpacingRight: 28,
visualSpacingTop: 12, visualSpacingBottom: 0, layoutMode: "fixedByHost"}`
(no side spacing: the channel page renderer passes
`omitHorizontalSpacing`). Loop audience: `messaging.fluidAudience`
("Preview" for this tenant). Teams' StylingProvider carries its theme as
658 CSS properties (Fluent's Teams tokens such as `--fontSizeHero800`
32px, the page title's size, and Teams' `--ms-theme*` names such as
`--ms-themeFontSizeHeading1` 18px, `--ms-themeColorBodyText` #242424) and
text styles for Heading 1-3 and Body. OST hands Loop the light theme as
measured (`desktop/src/loop_theme_light.json`); in its dark and high
contrast themes only the type, size and spacing tokens and the theme's
name (Teams' colours for those weren't measured).

## What Teams draws around it
- Chat notes: chat-tabs.md (the 48 px "Notes" header with the lock; the
  frame fills the rest: 862 x 506).
- A channel's Page (50 px header, a #E0E0E0 line): the page's name as a
  button (127 x 28 at 19, 10; the Loop file icon 20 px at 21, 14; the name
  12/16 semibold #424242 at 49) that opens it in Loop; Shared locations,
  Copy component and See who has access (32 x 32, #616161 glyphs, 15 from
  the right, 8 down). The frame fills the rest (862 x 504); Loop draws the
  page title ("Loop paragraph") and the insert row (Table, Bulleted list,
  Checklist, Task list, Voting table, …) inside it.
- New page's tab: "Untitled page" (the name stays; isTabNameSynced false);
  once the page exists Teams rewrites the tab property: `creatorUserMri`
  dropped, `componentUrl` added at the end of the settings (add-a-tab.md).

## OST's host (why this design)
- The arrangement is Teams': OST loads a host page with Teams' origin
  (`loadHtml(…, "https://teams.cloud.microsoft/")`), makes the same srcdoc
  frame, loads the same CDN driver and container code into it, and runs the
  loader in the host page's main world (the container's objects cross
  between the windows, as in Teams).
- The loader, the dependency synthesizer and the share-link URL resolver
  are the open-source Fluid Framework packages Teams bundles
  (`@fluidframework/container-loader`, `synthesize`, `odsp-driver`'s
  resolver; 2.118.1, MIT), bundled as `desktop/vendor/fluid-loader/
  fluid-loader.js` (global `OstFluid`; rebuild with `npm ci && npm run
  build` there). Teams' host glue (OfficeWebHost, its providers) is
  Microsoft's and is written anew from the behaviour above.
- Tokens come from Rust (`api::loop_page::token`): only SharePoint, the
  push channel, AugLoop, Graph and Substrate, as `<resource>/.default` from OST's
  browser sign-in (Teams' client); in memory until five minutes before
  expiry; never logged. They reach the page through a bridge script in an
  isolated world (it alone holds the web channel), by window messages from
  the same window.
- Not given (optional): presence colours, people suggestions for @, Teams'
  commanding surface, nested Loop components hosted by Teams, telemetry
  sinks, trusted-types policy (Loop falls back to its own handling).

## OST status (live checks 2026-11-16, ost-test1 on linuxlt, `--loop-test`)
- [x] A chat's Notes (OST group test) shows its Loop page in Loop's own
  page container under Teams' header (the placeholder 40 in and 22 down,
  the insert row 40 in and 16 above the bottom, as in Teams), with Teams'
  loading and error pages; "OST TEST" typed as real keys was saved (the
  page loaded again from the service showed it), then deleted again.
- [x] A channel's New page (OST test channel) adds the "Untitled page"
  tab; Loop makes "Loop paragraph" in the channel's folder (`POST
  …/root:/%2FOST%20test%20channel/Loop%20paragraph.loop:/opStream/
  snapshots/snapshot?createLinkScope=default&createLinkRole=edit`); the
  tab gets its link exactly as Teams rewrites it; the page shows with
  Teams' header, Loop's title and insert row, and takes typing. Teams on
  the web opened the page OST made. Page tabs that already have a link
  load in the same host, also in Open tab in new window.
- [ ] See who has access opens the page's link in the browser (Teams opens
  ODSP's permissions panel); presence colours, @ people suggestions,
  Teams' commanding surface and nested Loop components hosted by Teams
  aren't given to Loop; Loop's own telemetry sink and trusted-types
  policy aren't either; Teams' dark and high-contrast theme colours for
  Loop weren't measured (OST gives the theme's name and the light theme's
  type tokens there).
