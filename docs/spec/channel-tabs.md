# Channel and chat tabs — Teams desktop behaviour (spec)

Source: the Teams client itself (build 26276.513, Windows desktop). Its
modules were read from the published client bundles. They were checked
against the running Windows app on winpc, signed in as ost-test1, through
the WebView2 debugger. Module ids are given so this can be re-checked
against later builds.

## Components (module 454179: tab list and tab item; module 565846: header layout)
- **Tab item** (`Ut`/`Vt`) props: `isActive`, `isLive`, `tabItem`, `isOverflowEnabled`,
  `measuredWidth`, `maxTabWidth`, `moveTab`, `index`, `visualIndex`,
  `canMoveTabLeft`, `canMoveTabRight`, plus drag-and-drop refs.
- The **active** tab with a `submenu` shows a chevron button
  (`data-tid="tab-item-chevron"`). Clicking the active tab, or its
  chevron, toggles the submenu. Clicking an inactive tab dispatches
  `setActiveTabId`, unless the tab has `disableActive`.
- A **right-click** on a tab that has a `rightClickSubmenu` opens that
  menu, whether or not the tab is active.
- **Drag to reorder**: dnd-kit sortable. Tabs with `isNotDraggable` (the
  predefined ones) can't be dragged.
- **Move left / Move right flags**, set per rendered tab:
  - `canMoveTabLeft = !isNotDraggable && !isActiveOverflowPlaceholder`.
    It is forced false for the first draggable tab.
  - `canMoveTabRight = !isNotDraggable && index < lastIndex`. It is
    forced false when the tab list has overflowed.
- **Overflow**: tabs that don't fit (by measured width) move into an
  overflow list. Tab list props include `isOverflowEnabled`,
  `isDropdownAtSmallViewports` (at small widths the tabs collapse to a
  dropdown) and `maxTabWidth`.
- **Header layout** (`De`, module 565846) props: `emblem`, `title`,
  `accessories`, `tabsControl`, `fitTitleWidth`, `useEntireWidth`,
  `allowTabsToMoveUnderTitleAtSmallWidths`, `forceTabsUnderTitle`. At
  small widths the tabs move under the title. → TODO: read the exact
  breakpoints in 565846.

## Menu contents (module 277379, `We`; filters in module 542104)
Items are added in this order (`We`, the inputs):

| key | label (en-us) | added when |
|---|---|---|
| Popout | Open tab in new window | entry point is not a meeting, and sdkHostType == "Desktop". A real Page tab uses its own Page popout (`enableChannelPagesPopout`) |
| ExpandTab | Expand tab | entry point is Channel or Chat, and the `disableExpandTabAction` flag is off |
| Reload | Reload tab | always |
| GoToWebsite | Desktop: `stage_view_header_go_to_website_button_label` ("Open in browser"); else `open_in_new_window_button_label` | always |
| copyLink | Copy link to tab (`extension_tabCopyLinkMenuOption`) | entry point is not a meeting |
| ConfigDivider | — | always |
| Rename, Update | Rename; Settings (`platform_tab_update_settings_action_content`) | `isAllowedToUpdateTabs` and the tab is manageable |
| DevicePermissions | App permissions | the tab is manageable, the tab is an ExtensionTab or StaticExtensionTab, and its declared device permissions can be enabled |
| About | About this tab | always |
| MoveTabAccessibilitySection | Move left; Move right | the `enableMoveTabMenuItems` flag is on. Rendered as two items, **disabled, not hidden**, using the flags above |
| RemoveDivider, Remove | —; Remove | `isAllowedToUpdateTabs` and the tab is manageable |

Then each item is kept only if the per-tab filter allows it. A tab with
`baseInfo.isPredefinedTab` gets **no menu**. There are two filters:
- `c` builds the **submenu**, opened from the chevron on the active tab.
- `m` builds the **right-click menu**. It is the same as `c` but leaves out
  Reload and ExpandTab.

Per item, the tab types allowed:
- **Remove, RemoveDivider**: WebsiteTab, ExtensionTab, FileViewTab, PowerBiTab, OneNoteTab,
  LegacyDocumentLibraryTab, FolderTab, the Lists FileViewTab, LegacyWikiTab,
  the other kinds `r.Mp`/`r.LC`, the calendar app tab, and a real Page
  (ChannelPageTab that isn't `isLieChannelPageTab`). All need `isAllowedToUpdateTabs`.
- **Rename, ConfigDivider**: WebsiteTab, ExtensionTab, FolderTab, the Lists FileViewTab,
  LegacyWikiTab, the calendar app tab, and a real Page. All need `isAllowedToUpdateTabs`.
- **Popout**: ExtensionTab, FileViewTab, a real Page, and `r.Mp`; never the app `o.j`.
- **About**: ExtensionTab, WebsiteTab, FileViewTab, PowerBiTab, OneNoteTab,
  LegacyWikiTab, LegacyDocumentLibraryTab, `r.Mp`, `r.LC` and the calendar app tab.
- **copyLink**: ExtensionTab, WebsiteTab, FileViewTab, PowerBiTab, OneNoteTab,
  LegacyWikiTab, LegacyDocumentLibraryTab, a real Page, `r.Bp`, and the calendar app tab.
- **Reload** (submenu only): StaticExtensionTab, ExtensionTab, WebsiteTab, FileViewTab,
  PowerBiTab, OneNoteTab, LegacyWikiTab, LegacyDocumentLibraryTab and the calendar app tab.
- **ExpandTab** (submenu only): the same types as Reload.
- **Update**: needs `isAllowedToUpdateTabs` and `r.eb(tab)`.
- **DevicePermissions**: `r.g_(tab)`.
- **GoToWebsite**: the tab has a website URL (`r._p`) and `!r.n4`.
- **Move section**: always allowed.

## Verified on the live client (winpc, OST Test Team › General, 2026-11-06)
These are the tab items' resolved props, read through the WebView2
debugger, with `[key](kind)` as the client names them:

| tab | order | isNotDraggable | canMoveLeft / Right | submenu (chevron on the active tab) | right-click menu |
|---|---|---|---|---|---|
| Posts | 1 | yes | no / no | none | none |
| Shared | 2 | yes | no / no | expandTab, reloadTab, move section | move section |
| Page | 10 | no | **no** / yes | popOutChannelPage, copyLink, divider, renameTab, move section, divider, removeTab | the same |
| Notes | 10000 | no | yes / **no** | popOutTab, expandTab, reloadTab, goToWebsite ("Open in browser"), copyLink, divider, renameTab, devicePermissions ("App permissions"), aboutTab, move section, divider, removeTab | the same, without expandTab and reloadTab |

- The first movable tab can't move left, and the last can't move right.
  Both items are still shown, disabled.
- Shared (Files) is predefined but still has Expand tab and Reload tab.
  So the `isPredefinedTab` early return applies to Posts and the
  conversation tab, not to Files. → Check which flag Shared carries.
- New Pages are created at order 10 and Notes at 10000. Tabs added
  later take orders between these. OST's renumbering (×100) must not
  collide with them.

## Actions
- **Rename / Remove / Update** dispatch an action through the tab-actions
  hook (`q.r`), with `actionType` set to Rename, Remove or Update, the tab
  and app ids, the conversation and type, and `entryPoint: TabContextMenu`.
  The dialogs live in the `platform-modal` module. Rename's strings:
  `platform_tab_rename_dialog_title`, `platform_tab_rename_input_label`,
  `tab_rename_duplicate_name_error`, `tab_rename_empty_name_error`.
  Remove's: `remove_tab_dialog_remove_button`, `tab_remove_fail_error_message`.
  → TODO: read platform-modal for the dialog layouts and the service calls.
- **Copy link** builds a deep link from the host origin, the tab, a
  chat-or-channel flag, the conversation id, `subEntityId`, the team
  `groupId` and the tenant id (`Se.h`). If the tab has a display name,
  the clipboard gets rich text, so the link reads as the tab's name.
  A WebsiteTab with `enableDeprecateWebsiteTab` copies its website URL
  instead.
- **Copy link, exact format** (modules 137308, 407834 and 428148):
  - Link: `{origin}/l/{kind}/{a}/{b}?{query}`, where origin is the host
    page's (`https://teams.microsoft.com` on desktop) and:
    - kind `channel` (or `chat`): `a` = encodeURIComponent(conversationId), `b` = encodeURIComponent(tab.id);
    - if the tab has an `entityId`: kind `entity`, `a` = the app's definitionId,
      `b` = `_djb2_msteams_prefix_` + djb2(`${definitionId}:${entityId with "+"→" "}`).
  - djb2: `u = 5381; for each char: u = (ToInt32(u) << 5) + u + charCode`, and the result is `u >>> 0`.
  - Query, in this order:
    - `webUrl=` (only when there is a subEntityWebUrl);
    - `label=` (only when there is a subEntityLabel);
    - `context=` encodeURIComponent(JSON `{"subEntityId":…,"channelId":conv}`), or in a chat `{"subEntityId":…,"chatId":conv,"contextType":"chat"}`;
    - `groupId=`;
    - `tenantId=`.
  - Clipboard: HTML `<div itemprop="…"><a href="{link}" title="{link}" data-origin-known="true">{escaped tab name}</a></div>`, plus the link as plain text.
  - A WikiTab has no link.
- **Reload** routes by app: the calendar app, the Lists app, then
  "is it a Page tab?" (`U.yA`), and otherwise re-renders the tab with
  `reloadTabTrigger` toggled.
- **Expand tab** opens the tab full screen (`isFullScreenMode`) and calls
  `expandTabRequestCallback(true)`.
- **Move**: `moveTab(index, visualIndex ± 1)`. The order is saved through
  the middle tier's pinned tabs, `PATCH {mt}/beta/{scope}/{scopeId}/tabs`
  (`UpdatePinnedTabs`, module services-apps-platform). That is verified
  working from OST (commit f82a451).

## Tab order (worker modules 80574, 66811, 61009)
Constants: `orderLeftWall 100000`, `defaultOrderGap 10000`, `minOrderGap 50`,
`staticTabOrderBeginning 100`, `staticTabOrderGap 100`, `legacyOrderGap 100`.

**Moving** a tab gives only the moved tab a new `order`, saved with one
`UpdatePinnedTabs` PATCH of that tab. `newOrder(i, tabs)`, where `tabs` is
the list after the move and `i` the moved tab's new index:
```
mid(a, b): if a < WALL and b > WALL then a = WALL
           c = (a + b) / 2; f = floor(c); return f > a ? f : c
if i == 0 and len == 1:            WALL + GAP
elif i == 0 (or, in a chat, the left neighbour has no order):
    R = tabs[i+1].order
    R > WALL ? mid(WALL, R) : max(mid(0, R), R - MIN_GAP)
elif i == last:                    max(tabs[i-1].order, WALL) + GAP
else:                              mid(tabs[i-1].order, tabs[i+1].order)
```
**Adding** a tab: `last.order > WALL ? last.order + GAP : WALL + GAP`.

**New tab names** are made unique as `Name (n)`, where n is one more than
the highest existing number, matched case-insensitively against
`^Name$|^Name \((\d+)\)$`.

## Tab types (worker module: app id → kind)
- `com.microsoft.teamspace.tab.web` → webpage-tab (WebsiteTab)
- `…tab.extension` → extension-tab (ExtensionTab)
- `…tab.file` → files-tab
- `…tab.file.staticviewer.{excel,pdf,powerpoint,visio,word}` → files-pin-tab
- `…tab.files.sharepoint` → files-custom-spo-tab
- `…tab.notes` → notes-tab2
- `…tab.classnotes` → notes-class-tab
- `…tab.powerbi` → powerbi-tab
- `…tab.wiki` → wiki-tab
- `…tab.odata` → odata-tab
- `…tab.bot.query` → bot-query-tab
- `44263ed4-f1ac-4e96-93aa-d24dd50459ea` → calendar-tab
- `com.microsoft.teams.callable-channel` → callable-channel-tab
- `5ae80e49-7ada-461a-a6bd-c5df2e0cdb06` (Pages) → channel-page-tab (ChannelPageTab)

Files (`3ed5b337-…`, entityId `FileBrowserTabApp`) is a **StaticExtensionTab**.
That explains its menu: Expand tab and Reload tab only. A legacy OneNote
tab, with settings that include `sectionUrl` and `notebookId`, maps to
**OneNoteTab**. The current Notes app (`0d820ecd-…`, entityId NOTES) is
offered Rename on Windows, so it maps to an app tab (ExtensionTab).
Built-in chat tabs are BasicTab or StaticExtensionTab: Chat (order 1),
Chat Page (`com.microsoft.chattabs.chatnotes`, 3), Q&A and Whiteboard
(6), Storyline (7).

## Dialogs (module platform-modal)
Shared header (`dn`):
- the app's icon and name, when given;
- the title as an `h3` in semibold;
- a transparent **"About"** link button (`platform_app_configuration_about_link`) that opens the app's About dialog;
- a transparent **close X**, with the tooltip `platform_app_configuration_close_dialog` and the title.

**Rename** (`Gr`):
- Title: "Rename {{displayName}}".
- Label: "Tab name", with the error text next to it (`role=alert`).
- Text input: focused on open, holding the current name. At its end it shows a validity icon: a green check while the name is valid, a red filled dismiss icon while it isn't.
- Validation, on every change:
  - empty after trimming → "Name is required";
  - longer than **128** characters → "Tab name cannot exceed 128 characters.";
  - equal to an existing tab name (trimmed, case-insensitive) → "You already have a tab with that name. Try a different one."
- **Save** button: primary. Disabled while the name is invalid, and once clicked, so it can't be pressed twice. Enter in the field submits. There is no Cancel button; the header X closes the dialog.
- Saving:
  - GraphQL `updatePlatformTab` with `{threadId, tab: {id, displayName, appInstallScope, settingsForChannelPageTab: {isTabNameSynced: renameSettings.syncTabName ?? true}}, storageOptions}`. So renaming a Page renames the page too, by default.
  - The service behind it is the middle tier's pinned tabs (`UpdatePinnedTabs`).
  - On failure the dialog shows "Unable to save {{tabName}} tab configuration."

**Remove** (`$l`), for a tab with no remove listener:
- Title: "Want to remove this tab?". For a Page, "Want to remove this page?".
- Body: "The {{displayName}} tab will be permanently removed.". For a Page, "The page will be removed, not deleted. You can still access it from Microsoft Loop."
- One primary **Remove** button. It is disabled after the first click, and the label becomes "Removing". There is no Cancel button; the header X closes the dialog.
- On failure the dialog shows "We couldn't remove your tab. Please try later."
- Removing: GraphQL `removePlatformTab(threadId, tabId, tabType, storageOptions, options: {appInstallScope})`, then the client-side `updateTabDeletionResult`. The service behind it is the middle tier's `DeletePinnedTab`, `DELETE {mt}/beta/{scope}/{scopeId}/tabs/{tabId}`.
- A tab whose app has a `removeUrl` (remove listeners) shows "remove_tab_with_listeners_dialog_title", with the app's own remove page inside the dialog.

## Measured on the live client (CSS px at 150%, winpc)
- **Menu surface**: padding 4, radius 4, white, shadow `0 0 2px rgba(0,0,0,.12), 0 8px 16px rgba(0,0,0,.14)`,
  sized to its content (about 203 wide for the Notes menu).
- **Menu items**: 32 tall with a gap of 2, padding 6, radius 4, white.
  - Icon 20×20, then a 4 gap, then the label (14/20, #424242).
  - A disabled item's text and icon are #BDBDBD.
- **Dividers**: 1 device px, with 4 above and 4 below.
- The right-click menu opens at the pointer. The chevron menu opens below the tab.
- **Dialog surface** (Rename and Remove): width 600, padding 24, radius 8, white,
  shadow `0 0 8px rgba(0,0,0,.12), 0 32px 64px rgba(0,0,0,.14)`, centred on the window.
- **Dialog header**: starts 19.4 below the surface's padding.
  - Title: semibold, 16.38/20, #242424.
  - Then, at the right: "About", a transparent button 96×31.3 (padding 5/12, text #4F52B2 at 14),
    and the close button, 32×31.3 with a 20px dismiss icon in #424242.
- **Rename**:
  - "Tab name" label, 14/20, 20 below the header.
  - 10 below it, the field: 32 tall, #F5F5F5, radius 4, input padding-left 12,
    the full content width (550.7), and a 20px validity icon 10 from its right edge
    (check in #4F52B2 while valid).
  - 20 below the field, **Save**: primary, 96×31.3, #5B5FC7, white semibold 14, right-aligned.
- **Remove**:
  - The body text, 14/20 #242424, 20 below the header.
  - 20 below it, **Remove**: primary, 96×31.3, right-aligned.

## OST status against this spec
- [ ] Rename and Remove through the middle tier's pinned tabs (as Teams does), not Graph. OST uses Graph today.
- [ ] Chevron only on the active tab, and only when the tab has a menu. (OST: the ▾ shows on any selected tab.)
- [ ] Right-click menu on any tab (the `m` filter).
- [ ] Item order and visibility exactly as above, per tab type. (OST: five items, and it hides an unavailable move.)
- [ ] Move left/right disabled, not hidden; also disabled when the list has overflowed.
- [ ] Drag to reorder (not on predefined tabs).
- [ ] Overflow and the small-width dropdown; tabs moving under the title.
- [ ] Rename and Remove dialogs matching platform-modal (the empty and duplicate name errors).
- [ ] Copy link as Teams builds it (deep link, rich text with the tab's name).
- [ ] Reload, Expand, Open in new window, Open in browser, About, App permissions, Settings.
