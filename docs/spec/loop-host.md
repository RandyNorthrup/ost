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
`LoopPage.qml`, `LoopCommandingSurface.qml`, `ChatNotesTab.qml`, `ChannelPageTab.qml`,
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

## Teams' commanding surface (Loop's formatting toolbar)
Read from Teams 26304 (chat-app 425275 the provider, CommandingSurfaceV9
577697 the surface, 836862 the icons) and Loop's own chunks (Scriptor's
CommandingSurface service, 173848).
- Loop's CommandingSurface service uses the host's
  `CommandingSurfaceTreeViewProvider` when there is one; without it Loop
  draws its own toolbar inside the frame. Teams registers it when its
  fluid settings' `commandingSurfaceEnabled` is on (its default) and
  `enableRenderInDiv` is off: an EventEmitter with
  `get CommandingSurfaceTreeViewProvider() {return this}`,
  `display(params)`, `dismiss()`, `usesCoordinates: true`,
  `isExpandableCommandingSurfaceEnabled: true`, `get Disposable()`.
- `display` params: `{coordinates: {clientX, clientY}, topBarCommands,
  topBarCommandsOnExpand, mainBodyCommands, mainBodyInitiallyHidden,
  focusMode, previousElement, onDismiss, position, align}`. A command:
  `{id, displayName, ariaLabel, icon: "FFXC…" | iconProperties {name,
  color, backgroundColor}, toggle | canCheck, checked, disabled,
  shortcut, secondaryText, title, subMenuCommands, isInlineSubMenu,
  execute(event)}`; `{id: "divider"}` separates top-bar groups.
- Where: Loop's point is the selection's corner (+5 across) and, for a
  selection (collapsed: the top bar only), 50 px above it; for a
  right-click or Shift+F10 (expanded, focused) below it. Teams adds the
  hosting element's corner, padding and the page's scroll and puts a
  Fluent v9 Popover there (position `below`, align `start`, closeOnScroll,
  closeOnIframeFocus), in the legacy style (`useLegacyCommandingSurface`).
- Drawn: the popover (radius 16, NeutralBackground1, shadow 8, padding 8,
  200 to 320 wide); the top bar (`ul role=menu`, a flex row spread out,
  padding 0 4) of 32 x 32 subtle buttons with 16 px glyphs, toggles as
  `menuitemcheckbox` buttons, a command with non-inline subcommands a menu
  button, inline groups flattened; then Teams' "More" toggle (FFXCMore,
  string `commandingSurfaceToggleBtnText`) that shows or hides the rest;
  each button's tooltip its displayName. Expanded: a MenuDivider, then the
  main body's commands as Fluent MenuGroups (header = `title`) of items
  (14/20, the shortcut or secondary text in base200 at the end,
  checkmarks for toggles, submenus beside), a divider between groups.
- Measured on winpc 2026-11-21 (OST group test > Notes, text selected
  with the mouse): the popover 298.7 x 49.3 about 60 above the line,
  radius 16, padding 8, shadow `0 0 2px rgba(0,0,0,.12), 0 4px 8px
  rgba(0,0,0,.14)`; Bold, Italic, Underline, Strikethrough | Headings and
  lists | Color and formatting, Comment, More (32 x 32 each, the dividers
  8.7 wide; More on white with a #616161 glyph). OST's surface on the same
  selection: 298 x 48 with the same commands and glyphs.
- Picking: `command.execute(event)`, then Teams' dismiss: `provider.dismiss()`,
  `params.onDismiss()`, `params.previousElement.focus({preventScroll:
  true})`. Escape (Loop's own key binding while the focus is in the page,
  or the popover's), typing, deleting and a selection change make Loop
  call `dismiss()` itself.
- Glyphs: Teams maps 375 Loop icon names to SVG glyphs (Fabric MDL2 2048
  px and Fluent System glyphs), drawn in the text colour (`fill` from its
  icon style).

## Nested Loop components
Read from Teams 26304 (910716 the loader and hosting, 74043 its Loop
loader, 835081 the code loader) and Loop's chunks (Scriptor's unfurl
loader and its nested scope, 964793).
- Loop unfurls a Loop component link (or makes one: Insert, Create Loop
  component) with the host's `LoopComponentLoader.getLoopComponent({
  loopComponentRouterInput, dependencySynthesizer, fluidRequestHeaders,
  requiredProviderTypes})`; without one the link stays a link and
  creating fails ("CreateLoopComponent failed since LoopComponentLoader is
  undefined"). Loop builds the synthesizer from the page loader's scope
  (`ILoader.services`): the page's providers, the page loader's
  `urlResolver` (FluidUrlResolverProvider) and `documentServiceFactory`
  (FluidDocumentServiceFactoryProvider), `NestedComponentLevelsTracker`
  and its own services; `fluidRequestHeaders` `{isSharingLinkToRedeem:
  true}` (+ `X-CLP-Compliant-App` with information protection).
- Teams' getLoopComponent: a new Fluid loader with that driver, its code
  loader and the synthesizer wrapped with `NestedLoopComponentHosting`
  (`getNestedDependencyContainer`: as it is unless its
  `useNestedDependencyContainer` setting is on, the Automation audience)
  and a `ResolvedUrlProvider` for the new container (`getResolvedUrl`, and
  `resolveUrl(url)` through the URL resolver, cached). Router input
  `{type: "Data", dataType: "URL", data: {url}}`: the link must resolve to
  a Fluid file, then `resolve({url, headers: {loadMode: {opsBeforeReturn:
  "cached", deltaConnection: "delayed"}, ...fluidRequestHeaders}})`, the
  entry point (routed by the data-store path), `connect()`; `{type:
  "Fluid", codeDetails}` (or `pendingLocalState`): a detached container
  from the code details (or the snapshot). Then
  `ComponentInitializer.initialize()`, and the component goes back to
  Loop, which draws it in the page.
- Teams' code loader knows these packages, each from its family's
  versionless code load details on the CDN: `@fluidx/loop-page-container`
  (loopPageContainerCodeLoadDetails.json), `@ms/office-fluid-container`
  and `@ms/onenote-meetings` (container/versionless/
  officeContainerCodeLoadDetails.json, global `officeContainer`),
  `@fluidx/html-canvas-container`, `@fluidx/copilot-board-container` (and
  Whiteboard's, from whiteboard.office.com).

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
text styles for Heading 1-3 and Body. In dark and high contrast Teams
builds the same properties from its dark / high-contrast themes (dumped
from Teams' Loop frame on winpc 2026-11-20: 685 properties in light and
dark, 681 in high contrast) and names the theme `default`, `dark` or
`high-contrast`. OST hands Loop each as measured
(`desktop/src/loop_theme_light.json`, `loop_theme_dark.json`,
`loop_theme_contrast.json`).

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
- PresenceColorProvider (Teams' 478989): a collaborator's colour from the
  sum of the upper-cased id's character codes mod 10 over Teams' category
  colours (light #B24932 #92660D #56742F #248353 #164279 #37797B #7D2B5C
  #A22954 #764E3B #993840; dark #F39D89 #ECC26E #B5CC99 #78C9A0 #7FA3D0
  #96D6D8 #CC87B1 #E47CA1 #BF9D8C #DC8990; high contrast #1aebff).
- PeopleService (pages): @mention suggestions from the compose resolver,
  people only, as {userPrincipalName, name, id, jobTitle}.
- See who has access (Loop's header PermissionsPanel with Teams'
  ShareService): a popover "People who have access" with a facepile (32
  px, at most 6, then "+n"), the groups count, a line and what the widest
  link allows; from `{site}/_api/v2.1/drives/{d}/items/{i}/permissions`.
- A Page tab without a page: Teams hides one someone else made; it makes
  the page in your own (or one with no maker).
- The commanding surface: loop_host.js registers Teams' provider; each
  display goes to OST as plain data (each command with a key; the point
  in the host page's coordinates, numbered) and LoopCommandingSurface.qml
  draws Teams' legacy surface natively over the page (it may reach out of
  the frame, as Teams'). A pick comes back as `exec` (the command runs
  with a click event from the frame's window, then Teams' dismiss) and
  Escape, a click elsewhere in OST or (focused) into the page as
  `dismiss`; answers for an older display are dropped. The glyphs are
  Teams' (`assets/icons/loop-commanding.json`).
- Nested components: loop_host.js registers Teams' LoopComponentLoader,
  NestedLoopComponentHosting and ResolvedUrlProvider (also per nested
  container), and its code loader knows Teams' container families (the
  CDN allow-list stays).
- Not given yet: Teams' telemetry sink and trusted-types policy (Loop
  falls back to its own handling), Whiteboard's container, Loop's
  non-Fluid components (LoopCodeLoaderFactoryProvider) and the providers
  a nested component asks for by `requiredProviderTypes`.

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
- [x] 2026-11-20 (OST group test's Notes, `--loop-format`, `--loop-paste`):
  Loop hands its toolbar to OST's provider (Loop draws none in the frame);
  a mouse selection shows the top bar (Bold, Italic, Underline,
  Strikethrough | Headings and lists, Font color, Comment, More) above
  the text, reaching over the tab's header as in Teams; Bold picked there
  runs Loop's command (the text turns 600) and closes it; Shift+F10 shows
  the whole surface focused on Bold (Undo / Redo, Cut / Copy / Paste with
  their shortcuts, Increase / Decrease indent, Page width ▸, Link);
  Escape closes it. A pasted Loop component link (ost-test1's meeting
  notes) loads through the host's LoopComponentLoader and Loop draws the
  nested component in the page (its "Only some people have access" share
  prompt); removed again afterwards.
- [ ] Earlier items: see the 2026-11-16 notes in TASK-0205 / TASK-0207 for
  See who has access, presence and @ people suggestions. Not given yet:
  Loop's telemetry sink and trusted-types policy, Whiteboard's container,
  Loop's non-Fluid components, `requiredProviderTypes`. The commanding
  surface wasn't compared side by side with Teams on winpc (its metrics
  are from Teams' code); dark checked live (Shift+F10 surface), high
  contrast not. The harness's synthetic mouse selection doesn't always
  make Loop show the top bar (it did in one of three runs; Shift+F10
  always works).
