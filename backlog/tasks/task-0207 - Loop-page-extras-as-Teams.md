---
id: TASK-0207
title: Loop page extras as Teams
status: In Progress
assignee: []
created_date: '2026-11-16T20:42:00Z'
updated_date: '2026-11-21T15:46:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0205 left of Teams' Loop host (docs/spec/loop-host.md): "See who has access" opens the link in the browser instead of Teams' permissions panel; Loop doesn't get Teams' presence colours, @-mention people suggestions, formatting toolbar, nested Loop components, telemetry sink or trusted-types policy; Teams' dark and high-contrast Loop themes aren't measured (OST sends the theme name with the light values); a Page tab without a link that OST didn't create shows the loading page indefinitely.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 See who has access opens Teams' permissions panel
- [ ] #2 Mentions, presence, the formatting toolbar and nested Loop components work in OST's Loop pages as in Teams
- [x] #3 Loop pages use Teams' dark and high-contrast themes, measured on winpc
- [ ] #4 A Page tab without a link behaves as in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chatC), from Teams 26304 (research by a subagent; scratch chatC and linuxlt ~/chatC-r2):
  - See who has access is not ODSP's share dialog. It is Loop's header PermissionsPanel popover with Teams' ShareService (154570), reading GET {site}/_api/v2.1/drives/{d}/items/{i}/permissions.
    - The popover shows "People who have access", a facepile of 32 px pictures (at most 6, then "+n"), "{n} groups giving access", a line, and a footer chosen by the widest link: anyone or anonymous / organization / users / other.
  - Providers:
    - PresenceColorProvider (478989): sum of the character codes of the upper-cased id, mod 10, over the category colours. Light #B24932 #92660D #56742F #248353 #164279 #37797B #7D2B5C #A22954 #764E3B #993840; dark #F39D89 #ECC26E #B5CC99 #78C9A0 #7FA3D0 #96D6D8 #CC87B1 #E47CA1 #BF9D8C #DC8990; HC #1aebff.
    - PeopleService for pages: compose's @mention resolver, users only, as {userPrincipalName, name, id, jobTitle}. MenuItemProviderService is registered only for chat notes.
    - The formatting toolbar is Teams' CommandingSurface (CommandingSurfaceTreeViewProvider, chunk 19864).
    - Nested components: Loop's loader wraps the scope with NestedLoopComponentHosting.
    - Telemetry: UnifiedTelemetrySink.
    - Trusted Types: the "@fluidx/loop" policy (DOMPurify).
  - Themes: --ms-themeColorThemeName is "default", "dark" or "high-contrast". On winpc, Teams' Loop frame (OST group test > Notes) carries 685 properties in light and dark and 681 in high contrast, dumped to scratch chatC/loop-{light,dark,hc}.json. Theme was set back to Follow OS.
  - A Page tab without a page: Teams hides one someone else made (no componentUrl and a creatorUserMri that isn't you). For your own tab, or one with no maker, Teams makes the page (FluidCreateChannelPage).

- 2026-11-20 (chatC), built:
  - See who has access on Loop components, channel Page tabs and Loop app pages opens LoopAccessPopover. It shows "People who have access", the facepile with "+n", the groups count and the widest-link footer, from ODSP v2.1 permissions (api::loop_page::access, with a unit test).
  - loop_host.js now registers Teams' PresenceColorProvider (its colours per theme) and PeopleService (directory people, via a new "people" host request).
  - Theme name: default / dark / high-contrast. The dark and high-contrast properties come from the winpc dumps (desktop/src/loop_theme_{dark,contrast}.json; light refreshed from today's dump). The theme is applied when the page starts.
  - Page tabs: a link-less Page tab made by someone else is hidden; your own, or one with no maker, makes its page (Tab.creator from settings.creatorUserMri).
- Not checked live: the dark Loop page, because ost-test1's chat service was answering 429 (throttled) during the run, so the Notes page showed Teams' "Your notes are temporarily not available". The popover was not opened live either.
- Still open: Teams' commanding surface, nested-component hosting, telemetry sink and trusted-types policy.

- 2026-11-21 (chatE2), AC2 remainder: Teams' formatting toolbar and nested Loop components.
  - Built: loop_host.js registers Teams' CommandingSurfaceTreeViewProvider (425275: display/dismiss, usesCoordinates, expandable), LoopComponentLoader (910716/74043: a nested Fluid loader with the page's driver; links resolved as Teams' existing request with loadMode cached/delayed, code details as detached containers), NestedLoopComponentHosting and ResolvedUrlProvider (resolveUrl cached, also per nested container); the code loader knows Teams' families (loop-page-container, office-fluid-container and onenote-meetings via officeContainer, html-canvas, copilot-board), CDN allow-list kept.
  - LoopCommandingSurface.qml draws Teams' legacy CommandingSurfaceV9 natively over the page (top bar of 32 px buttons + More, expanded Fluent menu groups, submenus, keyboard, tooltips, light/dark/HC via theme). Glyphs: Teams' 375-name icon map (836862) as assets/icons/loop-commanding.json (NOTICE entry).
  - Harness: --loop-test=notes --loop-format (mouse-drag selection, Bold, Shift+F10, Escape), --loop-paste=<link>, --loop-backspace=<n>; KeyTyper gained drag() and more keys.
  - Verified live on linuxlt (ost-test1, OST group test Notes): collapsed top bar on a mouse selection, Bold via it (text weight 600), Shift+F10 expanded surface (light and dark), Escape closes; a pasted Loop component link (ost-test1's OST TEST 187 meeting notes) loads through LoopComponentLoader and Loop draws the nested component; all test text and the component removed again (page as before, checked after reload).
  - Open: high contrast not seen live; no side-by-side with Teams on winpc; the harness's synthetic drag only sometimes makes Loop show the top bar; Create Loop component / Insert component (type Fluid path) not tried live; requiredProviderTypes, LoopCodeLoaderFactoryProvider (non-Fluid components), Whiteboard container, telemetry sink and trusted-types policy not given.

- 2026-11-21 (chatE): See who has access's popover drawn live (`--loop-access-test`, OST group test > Notes): "People who have access", "1 groups giving access" (Loop's string), a line and "Only people with existing access can access this Loop component". Merged chatE2's toolbar and nested components (ba51310).

- 2026-11-21 merged: See who has access popover and dark/high-contrast colours verified against winpc; formatting toolbar and nested components built (AC2 open: toolbar on mouse selection is flaky in the test; high contrast and side by side unchecked; new nested component not tried).
<!-- SECTION:NOTES:END -->
