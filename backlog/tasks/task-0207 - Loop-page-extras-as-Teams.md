---
id: TASK-0207
title: Loop page extras as Teams
status: To Do
assignee: []
created_date: '2026-11-16T20:42:00Z'
updated_date: '2026-11-21T01:26:00Z'
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
- [ ] #1 See who has access opens Teams' permissions panel
- [ ] #2 Mentions, presence, the formatting toolbar and nested Loop components work in OST's Loop pages as in Teams
- [ ] #3 Loop pages use Teams' dark and high-contrast themes, measured on winpc
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
<!-- SECTION:NOTES:END -->
