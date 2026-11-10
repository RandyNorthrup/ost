# Chat list and conversation header — Teams desktop behaviour (spec)

Source: the Teams client itself (build 26276.513, Windows desktop). Its
modules were read from the published client bundles and from the data-layer
web worker (`precompiled-web-worker-inner_d`, `…inner_services_i`). They
were checked against the running Windows app on winpc, signed in as
ost-test1, through the WebView2 debugger (read-only: DOM, React fibers and
the live `coreSettings` values). Module ids are given so this can be
re-checked against later builds. Labels are the en-us strings, resolved from
the readable keys the code uses (`simpleCollab:…` unless another namespace
is shown).

"Live" below means the value that the winpc client (prod, ring R4,
tenant of ost-test1) has for a feature flag today. A clone should take
the live behaviour as the target. The other branches are listed so the
flag can be honoured later.

The list is internally called **SimpleCollab** (the "unified" chat +
channels list). It has three modes, read from `simpleCollabFilterType`
(hook `tn.f()`): `"CHATS"` (split view, Chat app), `"TEAMS_AND_CHANNELS"`
(split view, Teams app) and anything else = **unified** (the live mode:
one list with chats and channels). Every rule below says which mode it
applies to when that matters.

## Where things live

| part | module | notes |
|---|---|---|
| Left rail app (header, pills, sections, items, dialogs) | 855406 (chunk `simple-collab-app`, one 1.8 MB concatenated module) | |
| Per-item ··· / right-click menu (chats, channels, drafts, Copilot, quick views, communities) | 917728 (chunk 158033), entry `Fd` = `SimpleCollabMenuList` | |
| Team ··· menu | 274871 (`Xn`) | |
| Mark as read / unread item | 966819 | |
| Move to section submenu | 132655 | |
| Remove from section item | 406502 | |
| Generic tree row (title, bold, charms, badge, timestamp, hover ···) | 15856 | |
| Charm and badge picker | 336254 (`BB`, `lF`) | |
| Pill tags, pill hiding, filter helpers | 272479 | |
| All labels and many flags (GraphQL view data `OneGQL_SimpleCollabLeftRailViewData`) | `r_data-resolvers-browser-1gql-view-data` (each field = `stringTranslate("simpleCollab", key)` or a `coreSettings` read) | |
| Field resolvers that decide `can…` flags per conversation type | worker `inner_d`, type map `OneGQL_Team: le, OneGQL_ChannelConversation: Ke, OneGQL_OneOnOneChatConversation: Rt, OneGQL_BotChatConversation: it, OneGQL_GroupChatConversation: Ne, OneGQL_SelfChatConversation: nt, OneGQL_MeetingChatConversation: Mt`, header settings `OneGQL_SimpleCollabHeaderSettings: q` | |
| Rail width (resizable slot) | 708731 (`rL` min/max, per-breakpoint defaults), resize handle in async-entry 16100 | |

The labels are not hard-coded in components: each component reads a view
data field, and the resolver picks the string. So the label tables below
list the **field** and the **en-us text**.

## 1. Rail width (responsive)

The chat list is the `MID_NAV` slot of the app layout (module 708731).

| window width (`innerWidth`) | default list width |
|---|---|
| < 640 px | 0 (the list is not shown) |
| ≥ 640 px | 28rem = 280 px |
| ≥ 1280 px | 32rem = 320 px (winpc today: 1280 px wide → 320 px) |
| ≥ 1500 px | 36rem = 360 px |

(1rem = 10 px in Teams; confirmed: the slot reports `--slot-width: 32rem`
and measures 320 px.)

- The user can drag the divider. The width is clamped to **min 280 px,
  max 400 px** (`rL[IS_GREATER_THAN_0].min/max[MID_NAV]`; the same max
  at ≥ 1000 px).
- The divider is a `role="slider"` with `aria-valuemin=280`,
  `aria-valuemax=400`. ArrowLeft/ArrowRight on it resize; double-click
  resets to the default. With `enableResizableSlotsPolishedCursor` it
  also shows two small buttons, **Resize smaller** / **Resize larger**
  (`framework:resizable_divider_resize_smaller/larger`), which send the
  same arrow-key step.
- The filter pills inside the list overflow by measured width (see §4);
  nothing else in the list changes with width.

## 2. List header (module 855406, `Mb`)

Row: title on the left, then (in this order) **··· (More list
options)**, **Filter** toggle, [Meet now], **New message** button, **New
items ▾** button.

| element | shown when | details |
|---|---|---|
| Title `<h1>` | always | unified: `simpleCollabHeaderLabel` **"Chat"**; CHATS: `simpleCollabChatsHeaderLabel` **"Chat"**; TEAMS_AND_CHANNELS: **"Channels"** with `enableSimpleCollabSplitChannelsAppRename`, else **"Teams"** |
| ··· More list options | not the consumer (life) build (`hideSimpleCollabHeaderContextMenu` = environment is life) | §2.1 |
| Filter toggle | always | §2.2 |
| Meet now (icon only) | `calling.enableMeetNowInChatList` (live **off**) | |
| New message button | `enableSimpleCollabLeftRailHeaderNewMessageButton` (live on) and `simpleCollabHeaderSettings.canCreateNewMessage` and (mode ≠ TEAMS_AND_CHANNELS or `enableSimpleCollabNewMessageRename`) | §2.3 |
| New items ▾ | not the life build (`shouldHideHeaderPlusMenu`) | §2.3 |

With `core.enableHeaderEvolution` **and** `core.enableTabsPlusPlus`
(both live off) the header uses a different caption layout (`FL.r`,
`paddingStart: "midNav"`). Off: a plain heading row (`bL`).

### 2.1 ··· More list options (`$L`)

Trigger: transparent icon button, `data-testid="header-more-options-menu-trigger"`.
Tooltip always **"More list options"**. Its aria-label is **"More list
options. New items to try"** and it shows a small dot badge while
`showDotAndBadge` is on (a first-run "new items to try" state, at most
`simpleCollabFreMaxDaysToShowDotAndBadge` = 7 days). Menu: positioning
`below-start`, closes on scroll.

| # | label | shown when | action |
|---|---|---|---|
| 1 | **Mark all as read** (`markAllAsReadLabel`), shortcut Shift+Esc | always | see below |
| 2 | **Collapse all sections** (`collapseAllLabel`), shortcut Alt+Q | `enableSimpleCollabCollapseAll` (live on) and not life | collapse all sections |
| — | divider | not life | |
| 3 | **Customize view** (`simpleCollabLeftHeaderViewMoreSettingsLabel`), plus a **"Try it"** badge (`…TryItBadgeLabel`) while `showDotAndBadge` | always | opens Settings and focuses the settings search box (`enableJunoSearch`, live on) else the settings list; event `viewMoreSettings` |
| — | divider | not life and mode ≠ CHATS | |
| 4 | **Your teams and channels** (`simpleCollabLeftHeaderManageTeamsLabel`) | not life and mode ≠ CHATS | opens the Manage teams page in the main area; focus goes to its header |
| 5 | **Your communities** (`simpleCollabLeftHeaderYourEngageCommunitiesLabel`) | as 4, and `enableYourEngageCommunitiesEntryPoint` (= `enableSimpleCollabEngageCommunities && …JoinAndYourCommunitiesEntryPoints && isUserLicensedForEngage && engageCommunitiesAdminToggleEnabled`; live **on**) | opens Your communities |

**Mark all as read** is a **split item** in unified mode: the main part,
and a chevron (aria **"Mark all as read options"**) that opens a submenu:

| mode | main click | submenu |
|---|---|---|
| unified (live) | marks everything (`appType: "unified"`) | **All** (`unified`), **All chats** (`chat`), **All channels** (`channel`), **All communities** (`engage_community`, only with `enableSimpleCollabEngageCommunitiesMarkAllAsRead`, live on) |
| TEAMS_AND_CHANNELS | `split_channel` | with the communities flag: **All** (`split_channel`), **All channels**, **All communities**; without it: a plain item |
| CHATS | `chat` | none (plain item) |

- From the menu the action runs **at once, without a confirmation**.
- The **Shift+Esc** shortcut (`enableMAARKeyboardShortcut`, live on)
  shows a confirmation dialog first when `enableMAARConfirmDialog` (live
  on) and the user has not ticked "Don't ask again"
  (`clientPreferences.skipMarkAllAsReadConfirmDialog`). Dialog strings:
  title **"Are you sure you want to mark all {{entities}} as read?"**,
  body **"This will mark all your {{entitiesToBeMarked}} as read. This
  action can't be undone."**, checkbox **"Don't ask again"**, buttons
  **Confirm** / **Cancel**. Entities: **"chats"** (CHATS mode),
  **"channels"** (Teams mode), **"chats, channels, and communities"**
  (unified).
- Data: mutation `markAllAsReadByAppName(input: {appType})` → worker
  `startMarkAllAsReadWorkflow(appType)`. The optimistic update clears
  every unread/mention/important/urgent flag and badge count of every
  item and section that matches the app type (chats for `chat`, channels
  for `channel`/`split_channel`, communities for
  `engage_community`/`split_channel`, all for `unified`); quick-view
  sections are only cleared in the unified app.
  → TODO: the worker workflow's service calls.

**Collapse all sections**: mutation
`setConversationFoldersExpandedState(input: {appType: chat|channel|unified, isExpanded: false, filter})`.
The worker collapses every folder except, in the CHATS app, the Teams
and channels folder and, in the Teams app, the chat folders; it saves
through `conversationFolderManager.updateConversationFoldersExpandedState({folderIds, isExpanded})`
(conversation folders service, below).

### 2.2 Filter toggle and filter text box

- Button (`…sticky-filter-v2-button`), filter icon (filled when open).
  Label **"Show filter text box"** when closed, **"Close filter text
  box"** when open; tooltip shortcut **Ctrl+Shift+F** shown only while
  closed (`OpenLeftRailFilter`). Ctrl+Shift+F also opens it from anywhere
  and focuses the input.
- With `enableSimpleCollabSearchToggleButton` it is a toggle button with
  `title` = label + " (Ctrl+Shift+F)" instead of a tooltip.
- Text box (above the pills, animated in/out): placeholder and
  aria-label by mode — unified **"Filter by person, chat or channel
  name"**, CHATS **"Filter by person or chat name"**, Teams **"Filter by
  channel name"**. Clear button aria **"Clear filter text"**. Auto-focus
  on open. **Esc** closes it. Input longer than
  `simpleCollabFilterMaxCharacterLength` (live 100) is refused.
  Typing is debounced `simpleCollabFilterTextDebouceTimeInMS` (live 250
  ms) and then refilters the list (`filter.text`).
- No match: **"We didn't find any matches."** and a **Clear filters**
  button (`simpleCollabLeftRailEmptyResultLabel`,
  `simpleCollabLeftRailClearFiltersLabel`). Screen readers hear
  **"Filter active"**.

### 2.3 New message and New items ▾ (`Nb`)

- **New message** button (compose icon), tooltip **"New message"**
  (with `enableSimpleCollabNewMessageRename`, live on) else **"New
  chat"**, shortcut **Ctrl+N**. Opens a new chat; in a pop-out window when
  `alwaysPopOutNewChat` (user setting "open new chats in a new window").
- **New items** trigger: tooltip **"New items"**. Its icon is a chevron
  when the New message button is shown (the two read as one split
  button), else a plus. The menu opens `below`, aligned `end`, and it
  (re)loads `simpleCollabHeaderSettings` (store-and-network) each time.

Menu, unified mode (live), in order:

| # | label | shown when (worker resolver) |
|---|---|---|
| 1 | **New message** (`…CreateNewMessageLabel`; "New chat" without the rename flag), Ctrl+N | always |
| 2 | **New message in new window** (`…CreateNewMessagePopoutLabel`), Ctrl+Shift+N | `canOpenNewChatInPopOut` (`chat.enableNewChatPopOut`) and not `alwaysPopOutNewChat` |
| 3 | **New channel** (`…CreateChannelLabel`) | `canCreateChannel` (`teamsAndChannels.enableLeftRailAddChannelButton`, and NGC creation allowed) and not `enableSimpleCollabNewChannelInTeamMenuGroup` |
| 4 | **New storyline post** (`folderNewStorylinePostLabel`) | `canCreateStorylinePost` (storyline in 1:1 enabled, `allowStorylinePost`, storyline enabled in Teams, Engage enabled) |
| — | divider | before 5, when 5 shows |
| 5 | **Create agent** (`folderCreateAgentLabel`) | `canCreateTeamAgent` |
| — | divider | when any of 6–9 shows (`showTeamDivider`) |
| 6 | **New channel** (the "team group" placement) | `canCreateChannel` and `enableSimpleCollabNewChannelInTeamMenuGroup` |
| 7 | **Join team** (`…JoinTeamLabel`) | `canJoinTeam` (`enableReactJoinTeamsGallery`, not a guest) |
| 8 | **New team** (`…CreateTeamLabel`; life: TFL community label) | `canCreateTeam` (`enableCreateTeamSimplification`, not a guest, and the tenant's `isUserAllowedToCreateTeam`) or `canCreateTeamOnMainView` (`enableTeamCreateOnMainView`, not a guest) |
| — | divider | when 9 or 10 shows |
| 9 | **Join communities** (`joinEngageCommunitiesLabel`) | `enableYourEngageCommunitiesEntryPoint` |
| 10 | **New community** (`…CreateEngageCommunityLabel`) | `enableCreateEngageCommunityEntryPoint` |
| — | divider | not life |
| 11 | **New section** (`folderNewSectionLabel`) | not life |
| — | divider + bulk "move to section" item | `simpleCollabEnableBulkMoveToSection` |

CHATS mode: 1, 2, 4, [divider, 5], divider, 11.
Teams mode: like unified, but item 1/2 only with the rename flag and
`canCreateNewMessage`.

Actions: New team → `createTeam` (or `createTeamOnMainView` with
`canUserCreateTeam`); Join team → `joinTeam`; New channel →
`createChannel`; New section → the "Create a new section" dialog (§5.4).

## 3. Sections (folders)

The list is a tree (`role="tree"`). Level-1 rows are sections; inside
them, items; teams are level 2 with their channels at level 3. The
order and the set of sections come from the server's conversation
folders, not from the client:

`GET/POST/PUT/PATCH/DELETE {csa}/api/v1/teams/users/me/conversationFolders[/{id}]?supportsAdditionalSystemGeneratedFolders=true&supportsSliceItems=true`
(apiName `ConversationFolders`; same base as OST's conversations call;
extra query `setUnifiedForDesktop`, `hasUserVisitedSettings` on some calls).

Folder types seen in the client: `QUICK_VIEWS`, `FAVORITES` (legacy),
user-defined (`OneGQL_UserDefinedConversationFolder`), `RECENT_CHATS`,
`MEETING_CHATS`, `MUTED_CHATS`, `TEAMS_AND_CHANNELS`, `HIDDEN_CHANNELS`,
`RECENT_CHANNELS`, `TAG_SHARED_SECTION`, `ENGAGE_COMMUNITIES`, `APPS`,
`COPILOT`, `DISCOVER`, `SUGGESTED`, `UNKNOWN`.

Live order on winpc (DOM): **Copilot** (a single row, not a section,
`data-testid="list-item-metaos-copilot"`, from
`enableBizChatMetaOSSimpleCollabEntryPoint`), **Quick views**
(Mentions, Followed threads, Drafts), **Favorites**, **Chats**, **Teams
and channels**, **Communities** (with a **Join communities** row when
empty). Row heights: section header 32 px, chat 32 px, quick view 32
px, team 32 px, channel 28 px, "See all your teams" 28 px.

- **Quick views** content depends on mode
  (`quickViewsSupportedSlicesForViewType`): CHATS = Mentions, Saved,
  Drafts; Teams = Mentions, Followed threads (`Activities_Replies`), tag
  mentions, Discover, Saved, Drafts; unified = list in config (live
  shows Mentions, Followed threads, Drafts). A quick view gets the
  **New** badge for `quickViewsNewBadgeThresholdInDays` (14) days, except
  the slices in `quickViewsNewBadgeExemptSlices` (Discover, Inbox,
  Activities_Replies, Activities_Mentions, Activities_Mentions_Tag,
  Saved).
- **Chats**: first page `recentChatsInitialFetchCountOverride` = 25
  items (20 when the Meeting chats section exists), **See more** loads
  25 more (`…SeeMoreFetchCountOverride`). Meeting chats section: 5
  first, 10 per See more. Muted chats: 5 / 10. Communities: 10 / 10.
  Buttons: **See more**, and in "Unread only" view **See read**.
- **Teams and channels**: teams are expandable rows; channels under
  them. Hidden channels are not listed; **See all channels** opens the
  team. At the end **See all your teams** (`see-all-your-teams-button`,
  not in life) opens Manage teams. With
  `enableSimpleCollabTeamNameOverGeneralChannel` (live on) the General
  channel row reads as the team name where shown alone. A jump button
  ("Jump to" Teams and channels, `left-rail-teams-and-channels-jumper`)
  appears when the Teams section is scrolled out of view
  (`enableSimpleCollabLeftRailTeamsAndChannelsJumper`, live on).
- **Collapse**: each section header toggles `isExpanded`, saved through
  `setConversationFoldersExpandedState` / per-folder
  `useFolderExpandedStateSetExpandedStateMutation`. Teams expand/collapse
  with `SimpleCollabLeftRailTeamListItemSetExpandedStateMutation`;
  failures toast **"We couldn't expand the team."** / **"We couldn't
  collapse the team."**. Debounce 500 ms (`expandCollapseSectionDebounceInMs`).
- Keyboard: Alt+PageDown/PageUp next/previous section, Ctrl+Alt+Down/Up
  next/previous unread (both behind flags that are live **off**).
- Errors: **"We ran into a problem getting your chats and channels."**
  with **Retry**; partial: **"Some items didn't load."** / **"Some
  sections didn't load."** (banner flag live off).

### 3.1 Section ··· menu (`VC`, module 855406)

Trigger tooltip **"More section options"**
(`folderMenuMoreOptionsTooltip`); right-click on the header opens the
same menu. Positioning `below`, closes on scroll. Radio groups keep the
current sort/view.

| # | label | shown for |
|---|---|---|
| 1 | **Start reordering** | single-point reordering on (`enableSinglePointReordering`, live on) |
| 2 | **Manage tag** + divider | tag shared section the user can manage |
| 3 | **View ▸** — **All** / **Unread only** | `enableSimpleCollabConversationFolderShowOption` (live on). Switching while a filter is on toasts **"View switched to All. Clear filter to see all items in section."** |
| 4 | **Sort ▸** (radio) | not the Teams section, and sorting on (live on). Options are the folder's `sortTypes`; live config: user sections **Custom** + **Most recent**; Chats **Most recent**; recent channels **Most recent** + **A-Z** |
| 5 | divider, **Join communities**, **Your communities**, **Create community** | Communities section (with the communities entry-point flags) |
| 6 | divider, **Mark all as read** | `enableSimpleCollabFolderMarkAllAsRead` (live **absent → off**) and a chat / user / communities / channels-only section; mutation `markConversationFolderAsRead(folderId, filter)` |
| 7 | divider, **Rename section**, **Remove section** | user-defined sections |
| 8 | **Sort ▸ Most recent** (single option) | chat sections when sorting is off |
| 9 | divider, **Remove section** | Meeting chats and Muted chats sections; confirmation explains **"The meeting chats will still be available in your list. You can show the Meeting chats section again from Settings."** (`DisableSystemGeneratedConversationFolder`) |
| 10 | Teams section: **Display ▸ Teams and channels / Channels only** (when `canShowRecentChannels`), [Sort ▸ when Channels only], divider, **Hide inactive channels** (disabled with tooltip **"You can only take this action once every 24 hours."**), **Your teams and channels** (not life) | Teams and channels section |
| 11 | divider, **Copy Section ID** | developer mode |

### 3.0a Folder writes (Teams' worker ConversationFolderManager)

Every write carries the last `folderHierarchyVersion`.
- Create: POST `{folderName, sortType, isExpanded, actions:[{action:"AddFolder", itemId?}]}`.
- Items: POST `{actions:[{action:"AddItem", folderId, itemId, itemIndex} | {action:"RemoveItem", folderId, itemId}]}`.
- Update one section (rename, expand, sort): PUT `/{id}` `{folderName, isExpanded, sortType}`. System sections keep their type as the name.
- All sections: PATCH `/batchUpdateExpandedState` `{folderIds, isExpanded}`.
- Delete: DELETE `/{id}`.
- Your own sections come back with folderType `UserCreated`.
- Meeting chats and Muted chats need enableMeetingChatsFolder and enableMutedChatsFolder (both false in production), so they aren't listed.

### 3.2 Section dialogs

- Create: title **"Create a new section"**, placeholder **"Enter a
  section name"**, **Create** / **Cancel**; duplicate name: **"This
  section name already exists."** Sections can carry an emoji icon
  (**Add icon**, menu **Section icon**: **Change** / **Remove**).
- Rename: **"Rename section"**, subtitle **"The section will be renamed
  in both Chat and Channels."**, **Save**.
- Remove: **"Remove {0}?"**, **"The items in this section will still be
  available in your list."**, subtitle **"The section will be removed in
  both Chat and Channels."**, **Remove** / **Cancel**.

## 4. Filter pills (sticky filter, module 855406 `sI`/`Kh`)

Shown under the header when the user has not turned off "Show at top"
(`hasUserDisabledShowingFilterAtTop`, header context menu **Show at
top**). Each pill is a toggle button (`data-id` = tag). Labels:

| tag | label | shortcut (Windows) |
|---|---|---|
| UNREAD | **Unread** | Ctrl+Alt+U |
| TEAMS_AND_CHANNELS | **Channels** | Ctrl+Alt+A |
| NON_MEETING_CHATS | **Chats** | Ctrl+Alt+C |
| MEETINGS | **Meeting chats** | Ctrl+Alt+B |
| ENGAGE_COMMUNITIES | **Communities** | — |
| MENTIONS | **@Mentions** | — |
| MUTED / UNMUTED | **Muted** / **Unmuted** | Ctrl+Alt+Q |
| (clear all) | — | Ctrl+Alt+Z |

Which pills, in which order:
- With `disableSimpleCollabLeftRailFilterPillsOrderByConfig` false
  (live) the order comes from config. Live unified order:
  **Unread, Channels, Chats, Meeting chats**, then **Communities** (the
  resolver appends `ENGAGE_COMMUNITIES` when Engage is licensed and on).
  Split Chat app: Unread, Chats, Meeting chats. Split Teams app: Unread.
  **Unmuted** is appended when `showUnmutedFilterIfMutedSectionNotExist`
  and the user has no Muted section (live: flag absent).
- Without config (fallback): unified = Unread, [Unmuted], [@Mentions
  unless `disableSimpleCollabLeftRailAtMentionsStickyFilterPill` (live
  disables it)], Channels/Chats (order by a flag), and in the overflow
  group Meeting chats, [Muted].

Selection rules:
- **Category pills are single-select** (Channels, Meeting chats, Chats,
  Chats+meeting chats, Communities) with
  `enableSimpleCollabLeftRailFilterSingleSelectForCategoryPills` (live
  on): turning one on turns the other categories off. **Unread** combines
  with any category.
- The selected tags plus the text go into the list query filter
  (`{tags, text}`; the mode adds `COMBINED`+`SHOWN_AND_HOISTED`,
  `SPLIT_CHAT`, or `SHOWN_AND_HOISTED`+`SPLIT_CHANNEL`). The choice is
  saved (`updateSimpleCollabStickyFilter`) and restored next time
  (`enableSimpleCollabFilterUserPreferences`, live on).
- With Unread on, items read while the filter is on drop out of the list
  (`enableSimpleCollabLeftRailReadItemsRemovalInFilteredView`, live on);
  empty result shows **"You're all caught up!"** with **Clear filters**.

Responsive:
- The pill row is a Fluent toolbar with **width-based overflow**
  (`autoOverflow`). Pills that do not fit are not shown in the row;
  **selected pills have priority 1** so they stay visible.
- When anything overflows, a **More filters** button appears at the end
  (`…collapse-expand-filters-button`; tooltip and aria **"More
  filters"**; when open **"Fewer filters"**). It is hidden
  (`display:none`) when nothing overflows. Clicking it shows the
  overflowed pills on a **second row** (animated).
- Live at 320 px: row shows Unread, Channels, Chats + More filters;
  Meeting chats and Communities are in the overflow (measured: 0 px wide
  in the row).
- Optional cleanup (`enableLeftRailCleanup`, live **off**): a hideable
  pill (`simpleCollabHideablePillTags`) is hidden when its count is
  below `simpleCollabPillFilterShownThreshold` (3), unless it was shown
  once before (`simpleCollabShownPillTags` is persisted).

## 5. Items

### 5.1 What a row shows (module 15856 + 336254)

- Avatar/icon, title, optional external label **(External)** / **(SMS)**
  and trust indicator, optional message preview and timestamp.
- Previews/timestamps: per user setting; defaults
  (`simpleCollabMessagePreviewDefaults`): **unified: no previews, no
  timestamps**; split views: previews on, timestamps off. (Live: none.)
- **Bold**: the title gets the `unread` style when
  `activityStatus.hasUnreadMessage` **and the row is not an expanded
  branch** (`hasUnread && !treeItem.open`). So a team row is bold only
  while it is collapsed. The timestamp switches to `timestampUnread`.
  → TODO: the exact weights (Griffel classes `flh3ekv`, `fl43uef`; the
  CSS is injected at runtime only when used).
- Unread for chats = not read according to the conversation's
  consumption horizon (`originalArrivalTime;timeStamp;clientMessageId`)
  versus its last message; a chat with no last message counts as read
  (worker 98155 `Hi`).
- **Right side ("charms")**, live configuration
  (`enableBadgingVNextBrandColors` on, `enableBadgingExperimentShowDotOnFolder` on):
  1. **Followed** icon (threads you follow),
  2. **meeting in progress** icon (`hasActiveCalls`) or **huddle**,
  3. then one **brand badge**: a number when the row has a badge count
     (sections and teams), else a **dot** when the item
     `doesContributeToBadgeCount` (chats: unread **and not muted**).
  With brand colors off the old rules apply: if unread, urgent ›
  important › draft › reactions, plus mention › channel mention ›
  everyone › team mention; if read, meeting/huddle and draft only.
- Timestamp is shown only when there are no charms (or exactly one
  badge with anchor indicators).
- **"New" badge** (`newBadgeOnConversationItemLabel` **"New"**):
  - team: `isNewForUser` = the user joined it recently and has never
    read any channel in it (no channel has a consumption horizon > 0);
  - channel: never opened by the user; never on General.
  (Live: "Secure Coast Network Solutions" shows **New**.)
- Draft: a chat with only a local draft shows the preview **"Draft"**
  (`chatList:chatList_draft_chat_preview`), and its own menu (Open in new
  window, **Discard**). Empty drafts are auto-discarded
  (`enableSimpleCollabDraftChatAutoDiscard`).
- Typing indicator in the row (`enableSimpleCollabLeftRailTypingIndicator`, live on).
- Hover shows the ··· button (tooltips: **More chat options**, **More
  channel options**, **More team options**, **More community options**,
  **More Copilot options**, **More quick view options**). Right-click
  opens the same menu. The menu opens `below` the row, closes on scroll.
- Selecting an unread **community** row marks it read from the list
  itself (consumption horizon set to its last message time,
  `clientMessageId: "0"`, `mN` in 855406). Chats and channels are marked
  read by the conversation view when opened. → TODO: confirm in the
  conversation pane module.
- Keyboard focus moves selection after a short delay (focus follows
  selection, `rN` with a delayed-focus helper; seen on community rows),
  unless `disableAutomaticConvSwitchOnKeyboardNav`. → TODO: the delay.
  Ctrl+Enter opens the selected item in a new window (`PopoutSelectedItem`).

### 5.2 What appears in the Chats section

Server-side: the conversation folders service decides membership
(`RECENT_CHATS`, `MEETING_CHATS`, `MUTED_CHATS`, user folders). The
client only filters and hoists:
- **Hidden chats** are not listed (`isHidden`, worker 29941 `lb`): a
  chat the user hid stays hidden until a message newer than the hide
  time arrives; a meeting chat whose RSVP is **Declined** is hidden when
  RSVP-based meeting-chat notifications are on, until it is unhidden
  later; a chat converted to a channel is hidden.
  → TODO: the exact property names behind the hide time.
- A hidden item that becomes selected (e.g. from search or a link) is
  shown temporarily ("temp hoist", `hasTempHoist`); channels are hoisted
  for `channelTempHoistThresholdInSeconds` (30 s).
- Meeting chats go to the **Meeting chats** section when it exists,
  else stay in Chats. The **Meeting chats** pill filters to them.
- Sorting inside a section: the section's `sortType` (Chats: Most
  recent; user sections: Custom or Most recent). Recency uses the last
  message arrival time; selecting an item snapshots and re-sorts
  (`enableSnapshotAndSortOnConversationSelect`).

### 5.3 Drag and drop, reordering

- dnd-kit sortable tree (`simple-collab-dnd-rail`). Mutations:
  `useReorderConversationFoldersMutation` (sections),
  `useReorderConversationFolderItemsMutation` (items inside a Custom
  sorted section), `useReorderTeamsInTeamsAndChannelsFolderMutation`
  (teams), `useDndItemToConversationFolderMutation` (move an item into a
  section). Each item carries `allowedSystemGeneratedFolderToDropInto`;
  invalid drops are refused (`ITEM_NOT_COMPATIBLE_WITH_FOLDER`,
  `FOLDER_CAN_NOT_BE_DROPPED_TO_ITEM`).
- Keyboard alternative: **Start reordering** in a menu shows move
  buttons on the row (single-point reordering, live on).

### 5.4 Chat ··· menu (module 917728 `go`)

Live uses the **classic** layout (`teamsAndChannels.enableSimplifiedContextualMenus`
is absent). Order (each line only when its condition holds):

| # | label | condition |
|---|---|---|
| 1 | **Open in new window** | `canOpenInPopOut` = `chatList.enablePopoutAction` (live on) |
| 2 | **Start reordering** | single-point reordering on and allowed in this section |
| — | divider | if 1 shows |
| 3 | **Mark as read** (when the chat is unread) / **Mark as unread** (when read) | `canMarkAsReadUnread` (true; self chat only with a last message) |
| 4 | **Move to section ▸** | always. Submenu (module 132655): one item per `possibleFolderDestinations` edge (disabled ones greyed), divider, **New section**, then **Remove from section** when allowed. In the old favourites-only mode (life) it is a single Favorite/Unfavorite item instead |
| 5 | **Remove from section** | the chat is in a user section (`canBeRemovedFromFolder`) |
| 6 | **Mute** / **Unmute** | not the self chat; group chats only when the user is a member |
| 7 | **Notify when available** / **Turn off notifications** | 1:1, `participant.canFollowPresence`, `presence.enableFollowPresence` (live on) |
| 8 | **Block bot conversation** / **Unblock bot conversation** | bot chats |
| 9 | **Manage apps** | `canManageApps` |
| 10 | **Set workflows** | `canOpenWorkflows` |
| 11 | **Copy link** | `canCopyLinkToChat` = `chat.enableCopyLinkToChat` (live on); toast **"Copied to clipboard"** |
| — | divider | if any of 12–15 shows |
| 12 | **Leave** | `canLeave` (below) |
| 13 | **Delete** | `canDelete` (below) |
| 14 | **Hide** / **Unhide** | `canHide` and `enableSimpleCollabHideChat` (live on). (In the life build Hide sits above, before the divider.) |
| 15 | **Block** / **Unblock** | `canBlock` (1:1 only) |

**The menu and Mute, measured live** (winpc, ost-test1, "OST group test", 2026-11-07):
- **The menu.** 170.2 wide; items 32 tall and 2 apart; dividers 12.7 between items.
  - A group chat's menu reads: Open in new window | Mark as read, Move to section, Mute, Manage apps, Set workflows, Copy link | Remove chat history, Hide.
  - Icons (regular): Open, Glasses (Mark as read), MailUnread (Mark as unread), Star (Move to section), AlertOff (Mute), Alert (Unmute), Link, Delete, EyeOff (Hide).
- **Mute** writes `PUT {chatsvc}/v1/users/ME/conversations/{id}/properties?name=alerts` with `{"alerts":"false"}`; **Unmute** writes `{"alerts":"true"}`.
  - The state comes back in the conversation list as `properties.alerts`.
- **A muted row** replaces the picture with a 20 px #E6E6E6 circle holding the regular AlertOff icon (16, NeutralForeground3) at 2, 2.
  - The name is still bold when unread, but there is no badge dot.
  - Muted chats don't count toward the Chat badge.
  - They notify only for @mentions ("You're only notified of @Mentions"); the Meet now toast is dropped for them (527114 `sMe` "ConversationMuted").
- **On hover**, ··· ("More options", 20 px) shows at 258, 6 in the 288-wide row, in place of the charms.
| — | divider, **Report a concern** | meeting chats with `canReportMeeting` and tenant policy `teamsMeetingConfiguration.reportMeeting == "ENABLED"` |
| — | divider, **Copy Conversation ID** | developer mode |

Worker rules (inner_d):

| type | canLeave | canDelete | canHide | canBlock |
|---|---|---|---|---|
| 1:1 | never | `enableSimpleCollabDeleteChat` and `messaging.allowUserDeleteChat` (live: both on) | yes | `enableSimpleCollabBlockChat` + federation / in-org blocking rules |
| group | the user is a member **and the chat has ≥ 3 members** (`Oc.JF = 3`, module 17475) | delete flags **and the user can't leave** (fewer than 3 members) | yes | no |
| meeting | member, ≥ 3 members, **and the user is not the meeting's creator** | only in the consumer (life) build | yes | no |
| self | never | life only | yes (work) | no |
| bot | never | delete flags (or life) | yes | no |

Mark as read/unread uses `setConversationConsumptionHorizon` (+
`…Bookmark` when marking unread) with the last message's
`clientMessageId`/arrival time; the screen reader hears **"Chat marked
as read"** / **"Chat marked as unread"**.

### 5.5 Channel ··· menu (module 917728 `ul` = `ml` + `sl` + `cl`)

| # | label | condition |
|---|---|---|
| 1 | **Open in new window**, divider | `channels.enableChannelL1ViewPopout` (live on) |
| 2 | **Channel notifications** | `canShowNotificationSettings != "HIDE"` (disabled when `"DISABLE"`); needs `activity.enableChannelNotificationSettingsInT21` |
| 3 | **Start reordering** | single-point reordering |
| 4 | **Move to section ▸** | `canShowMoveToMenu != "HIDE"` (hidden in archived teams; disabled when `"DISABLE"`) |
| 5 | **Remove from section** | not opened from the team hierarchy, and the channel is in a user section |
| 6 | **Hide** / **Show** | `canTogggleVisibility` and the caller allows it; never for archived channels; General only with `enableGeneralChannelShowHide` (live on) |
| 7 | **Join** | interest-vs-access model only (`channels.enableInterestVsAccess`, live off) |
| — | divider | if any of 2–7 shows |
| 8 | **Add people** | `canAddMembers` and `enableInterestVsAccessAddPeople` |
| 9 | **Add members** | `canAddMembers`, private channel, not interest-vs-access |
| 10 | **Share channel ▸ With people / With team / With a team you own** | owner of a shared channel (rules `za`) |
| 11 | **Edit channel** | `canEdit` (below) |
| 12 | **Manage channel** | always |
| 13 | **Manage team tags** | `canShowManageTeamTags`, not from hierarchy, not `shouldHideGoToTeam` |
| 14 | **Manage channel tags** | `canManageChannelTags` |
| 15 | **Copy link** (when `canCopyLinkToChannel` = `enableCopyLinkToTeamsAndChannels`, live on) else **Get link to channel** | `canGetLinkToChannel` (standard; private/shared only with their deep-link flags) |
| 16 | **Get email address** | `canGetEmail` |
| 17 | **Workflows** | `canShowChannelWorkflows` |
| 18 | **Recommend for everyone** / **Stop recommending for everyone** | `canSetRecommendation` and the caller allows it |
| 19 | **Go to team** | not from the team hierarchy and not hidden by the caller; disabled for channel-only members |
| — | divider | if any of 20–22 |
| 20 | **Leave channel** | `canLeave` (private, or shared where allowed) |
| 21 | **Archive channel** / **Restore channel** | `canArchiveRestoreChannelContextMenu` (live on) and `canArchiveRestoreChannel` |
| 22 | **Delete channel** | `canDelete`: not General, team not archived, and (team owner, channel owner, or — standard channels — the team's member setting `deleteTopic`; guests also need the guest setting) |
| — | divider, **Copy Conversation ID** | developer mode |

`canEdit`: not in an archived team; General only with
`enableRenameGeneralChannel` (live on) and team owner; otherwise owner,
or member with the `createTopic` setting for standard channels.

### 5.6 Team ··· menu (module 274871 `Xn`, classic)

| # | label | condition |
|---|---|---|
| 1 | **Hide all channels** + divider | `enableSimpleCollabShowHiddenTeams` (live on), the team has at least one shown channel, not interest-vs-access. Confirmation: **"Hide all channels in {TeamName}?"**, **"Channels will be removed from custom sections they're in, and if they're shared channels, hidden from teams they're shared with."**, **Hide** / **Cancel** |
| 1′ | **Show** / **Hide** (team) | only when `enableSimpleCollabShowHiddenTeams` is off |
| 2 | **Start reordering** | single-point reordering |
| 3 | **Add member** | `canAddMember`: owner, or public team (not class/locked) or private team member; never guests or archived teams |
| 4 | **Add channel** | `canAddChannel`: owner; guest with guest `createTopic`; member with `createTopic` (or NGC private-space permission) |
| 5 | **Manage team** | not a channel-only member |
| 6 | **Manage tags** | not a channel-only member |
| 7 | **Copy link** (with `canCopyLinkToTeam`) else **Get link to team** | not a channel-only member |
| 8 | **Archive** / **Restore** | `canArchiveRestoreTeam` |
| — | divider | if 9 or 10 |
| 9 | **Leave** | `canLeave` (not for archived teams; restricted for non-owners of org-wide/locked teams) |
| 10 | **Delete** | `canDelete` = team owner and not archived |
| — | divider, **Copy Team ID** | developer mode |

#### 5.6.1 Add members to {team} (measured 2026-11-09)

- 600 × 483, padding 24, radius 8. **Add members to {team}** (20/28
  semibold); the guidance (14/20, 543.5 wide): "Start typing a name,
  distribution list, or security group to add to your team. You can also add
  people outside your organization as guests by typing their email
  addresses. People outside your org will get an email letting them know
  they've been added." and **Learn about adding guests** (#4F52B2,
  underlined) →
  `https://support.microsoft.com/office/add-guests-to-a-team-in-teams-fccb4fa6-f864-4508-bdde-256e7384a14f`.
- Picker (Fluent TagPicker) 128.7 down: 550.7 × 33.3, #F0F0F0, radius 4,
  padding 0 12, "Type a name or email" (#424242); focused: 2 px brand
  underline and a chevron. Search:
  `POST {mt}/beta/users/searchV2?includeDLs=true&enableGuest=true&includeBots=true&skypeTeamsInfo=true&source=addToTeam`
  with the query as the body. Matches under the picker (padding 4; options
  50 tall, padding 6 8: picture 32 at 12, the name 14/20 #424242 and its
  second line 12/16 #616161 at 60, the typed part bold); people show their
  UPN alias in capitals ("RANDY"), groups their address. Team members are
  left out. An address matching nobody: **Add {email} as a guest?** (bold
  address, grey person picture).
- Picked rows from 172 down (546.7 wide, 44.7 tall, #E0E0E0 line): picture
  32 at 8, name 14/20 and e-mail 12/16 #616161 at 56; a group's name is
  followed by an expand button ("Expand the list with 1 person" / "…{n}
  people") that replaces it by its people; role dropdown (transparent,
  112.3 × 30 at 384.3; **Member/Owner**, for a group **Members/Owners**;
  list 127.6 wide with a check on the chosen one); Remove (32 × 31.3) at
  501.6. Guests: **Add name** (brand semibold; opens "Enter a name for
  {email}" with Cancel / Save in place), the address, a **Guest** tag (12
  semibold #616161 on #EBEBEB, radius 4).
- **Cancel** / **Add** (96 × 31.3) 403 down; Add is disabled until someone
  is picked.
- Adding: `PUT {mt}/beta/teams/{teamThread}/bulkUpdateRoledMembers?allowAsyncAddition=true`
  `{"users": [{"mri", "role": 0 member | 1 owner}], "groupId"}` (the
  middle tier's role numbering, from Teams' bundle); a group adds its
  people (OST reads them from Graph `transitiveMembers`); guests:
  `PUT {mt}/beta/teams/{teamThread}/{groupId}/inviteAndAddGuest`
  `{emailAddress, displayName, enableInviteTeamsNotification, userType:
  "Guest"}`. When some fail: "{n} of {m} members were added", "{k} people
  couldn't be added" / "1 person couldn't be added", "There were some
  errors." / "There was an error.". Not exercised live: the test tenant
  allows no new team members.

#### 5.6.2 Manage tags (Manage team ▸ Tags, measured 2026-11-09)

The team menu's **Manage tags** opens Manage team on its **Tags** tab.

- List (offsets from the tab area): **Search for tags** (170 × 32, search
  glyph at its end) 72 in, 32.3 down; **Create tag** (brand, tag glyph) 52
  from the right. Sections 80 in, 82.3 down, 44 tall headers (chevron 20 at
  10, label 14/20 at 38): **Tags assigned to you (n)** (open; empty: "No
  tags are currently assigned to you"), **Other tags (n)**, **Deleted
  (n)**. Tables 12 further in: header 34 (12/16: Name, Members,
  Description, Imported from; five equal columns), rows 44 with a #FAFAFA
  line: round badge 32 (#C5CBFA, tag glyph #444791), name 14/20, the people
  glyph and the count, description, source, ··· (32 × 31.3): **Chat with
  group**, **Create a copy** | **Delete**. Deleted tags offer **Restore**.
- A tag (click its row): **All tags** (chevron, 600) 72 in; **Add people**,
  **Edit tag details**, **Create a copy** | **Delete tag** (32 × 31.3) 84
  from the right; badge 42 at 96 and the name 16/22 bold at 150, 100.3
  down; **Members (n)** (14/20 bold) 190.3 down, then Name, Title,
  Location, Organization (rows 44: picture 32 with presence, Remove).
- Dialogs (Northstar: 600 wide, padding 27 32 32, title 18/25.7 bold):
  **Create a new tag** (594.7: Tag name * with n/40 while focused, filled
  field "Letters, numbers, spaces and emojis are allowed"; Tag description
  with n/200 while focused, "Let people know what this tag is all about";
  "Enter name of a member" * with an underlined picker "Enter name", 43
  tall matches with 28 px pictures, "We couldn't find any matches.", the
  picked people below; Cancel / Create), a copy starts "{name}_copy" with
  the tag's people; **Edit tag** (364.7; Save once changed); **Add people**
  (594.7); **Are you sure?** (164.7: You're about to delete the "{name}"
  tag.; Cancel / **Delete tag**). Only owners change tags when the team's
  `onlyOwnersCanUpdate` is set.
- Wire (CSA, chatsvcagg token; `{team}` = the team thread):
  list `GET {csa}/api/v1/teams/{team}/tagCards?tagType=any` (+
  `teamTagSettings`) and `…/deletedTags`; members
  `GET …/v1/teams/{team}/tags/{tag}/members?pageSize=200`; create
  `POST …/v1/teams/{team}/tags` `{threadId, tagName, tagDescription,
  memberIds}`; edit `PATCH {csa}/api/v2/teams/{team}/tags/{tag}`
  (`if-match` its version) `{tagName, tagDescription}`; delete
  `DELETE …/v1/teams/{team}/tags/{tag}`; restore `POST …/tags/{tag}/restore`;
  people `POST …/v1/teams/{team}/memberTags?tagType=team&action=add`
  `{memberIds, tagNames}` / `action=delete` `{memberIds, tagIds}`. Member
  search: the team profile search (§7.7.1). Chat with group opens New chat
  with the tag's people. Verified both ways on "OST test tag" (description
  set in Teams, read and cleared from OST).

#### 5.6.3 Archive, Leave and Delete (measured 2026-11-09)

Dialogs: 600 wide, padding 20 30.7 32, radius 8, title 18/28 semibold,
text 14/20 36 down, buttons 96 × 31.3 (8 apart) at the right.

- **Archive** (owners; 200.7): "Want to archive the {team} team?" / "This
  will freeze all team activity, but you'll still be able to remove members
  and update roles. Go to **Manage teams** to restore the team." / checkbox
  "Make the SharePoint site read-only for team members" / Cancel, Archive.
  `POST {teamsAndChannelsProvisioningService}/groups/{group}/archive[?setSpoSiteReadOnlyForMembers=true]`
  (templates token); an archived team's menu offers **Restore team**
  (`…/groups/{group}/unarchive`) and drops Add member, Leave and Delete.
- **Leave** (128.7): "Are you sure you want to leave the {team} team?" /
  No, Yes. `PUT {mt}/beta/teams/{teamThread}/members` `{"userMri",
  "updateType": "DemotedAndLeft", "groupId"}` → `{errorCode}`;
  `OperationDeniedAsMemberIsLastAdminInTeam` shows "The last owner can't
  leave the team" / "You're the last owner of the {team} team. There has to
  be at least one other owner for you to leave the team." / OK; other codes
  toast "Leaving the team failed".
- **Delete** (owners; 220.7): "Delete the {team} team" / "Are you sure you
  want to delete the **{team}** team? All hosted channels, conversations,
  files, and the Microsoft 365 group for this team will be deleted. You'll
  lose access to any shared channels that have been shared with the team."
  / "I understand that everything will be deleted" (Delete team waits for
  it). `DELETE {mt}/beta/teams/{teamThread}/delete`.
- Verified from OST: Leave as the last owner (the service refuses, OST
  shows Teams' dialog); Archive (Teams drops the team from its list) and
  Restore team (it returns). Delete is not run.

### 5.7 Communities, Copilot and quick views

- Community menu (`Wo`) has these items: **Hide**, **Delete**
  (confirmation **Delete**/**Cancel**), **Leave** (confirmation
  **Yes**/**No**), **Mark as read**, **Copy link**. → TODO: render
  order and conditions (the list above is definition order).
- Quick view menu: **Open in new window** (`canOpenInPopOut`), **Start
  reordering**, divider, **Show ▸ Always / When unread** (slice
  gestures), divider, **Hide**.

## 6. Keyboard shortcuts in this area (Windows desktop keymap, async-entry)

| command | keys |
|---|---|
| New chat | Ctrl+N |
| New chat in new window | Ctrl+Shift+N |
| Open filter | Ctrl+Shift+F |
| Mark all as read | Shift+Esc |
| Collapse all sections | Alt+Q |
| Toggle Unread / Channels / Chats / Meeting chats / Muted pill | Ctrl+Alt+U / A / C / B / Q |
| Clear all filters | Ctrl+Alt+Z |
| Open selected item in new window | Ctrl+Enter |
| Next / previous section | Alt+PageDown / Alt+PageUp (flag off) |
| Next / previous unread | Ctrl+Alt+Down / Ctrl+Alt+Up (flag off) |

## 7. Conversation header

Checked live only on a channel (OST Test Team › General, Page tab
selected; the window could not be navigated). The chat claims come from
the code plus the live flag values.

### 7.1 Components

| module | what |
|---|---|
| 565846 | Generic `EntityHeader` (`st`) for every header: `De` title/tabs layout, `_e` toolbar (`data-tid="entity-header-toolbar"`), `we` action area, `Qe`/`Ze` context-area icon buttons, `Fe` ··· overflow menu, `Oe` context-area limits, `Je` close X |
| 662465 / 176312 / 7260 | Breakpoints. `useBreakpoints` (`RF`) reads the nearest responsive container, measured by a `ResizeObserver` (`contentRect.width`, 250 ms debounce). `isMinWidthBreakpointAtLeastN` = **container** width ≥ N; `…ViewportBreakpoint…` = `window.innerWidth` ≥ N |
| 300780 (chat-app chunk) | Chat header: `Xy` → `qy` → `Fp`/`Ap`; `Yg` action area, `hv`/`fv` context area, `bv`/`p0` ··· menu, `uf` title accessories incl. rename pencil `cf`, `pc`/`Dv`/`xv` title, `Ko` participant count, `Wg` roster, `Ug` Meeting details, `hy` tabs from `tabsConnection` |
| 541159 / 156936 | Chat call-button dispatcher / implementations (`mn`,`en`,`an`,`pt` 1:1 button + "More call options"; `Ln` group Meet now; `q` Join) |
| 775523 | Show predicates for chat ··· items (`v` leave, `up` delete, `Lo` mute, `No` notifications, `E7` pin, `Be` read state, `aO` pop-out, `rc` share app) |
| 63701 / 612675 / 456660 | 1:1 add-people button / chat Copilot button / "is the Chat tab selected" |
| 354958 (chunk 177792) | Channel header: `yu` layout, `Wt` toolbar config, `ks` action area, `ul` context area, `Si`/`ws` ··· menu, `Ul`/`zl`/`yl` Meet now, `Kl` tab-conversation button, `jo` info pane, `Ot` Find |
| 82632 + 626114 | Channel context-menu builder used by the channel header ··· (`KD` options, `HE` items, `Nc` render) |
| 454179 / 961009 | Tab list (dropdown below 640) / built-in tab definitions; worker `inner_d` `Ct` filters built-in chat tabs |
| 144453 / 141472 / 616373 / 633979 / 615413 / 691027 | Group-name limits / chat-policy gate / Copy link / Mute / Leave / Delete |

### 7.2 Layout (565846)

- Header box 61 px high, padding `0 7px 0 20px`, background
  `colorNeutralBackground3` (live rgb(250,250,250)), bottom border 1 px
  `colorNeutralStroke2` (live rgb(224,224,224)); no border when
  collaborative tabs show (`entityHeaderNoBorder`).
- Title area: 8 px gap, min-width 30 px (90 px with an emblem),
  `fitTitleWidth` → `min-width: fit-content`; max-width 80 % when there
  are no tabs. Emblem slot 3.2rem (live 32×32 avatar). Title `h2` is
  **18 px / 700** (line-height 25.7 px live); chat description line 12
  px regular `colorNeutralForeground4`. Accessories (pencil, recurring
  icon) sit right of the title.
- Tabs follow the title in a `flex-grow:1; height:100%` wrapper.
- Toolbar: `margin-left:auto`, padding `0 4px`. Order: **action-area
  items** (those not moved to overflow), a **divider** (16×24, padding 0
  8px, `colorNeutralStroke3`; shown when there is a visible action item
  and context items or ··· items exist; suppressed with
  HeaderEvolution+TabsPlusPlus, both off), **context-area icon buttons**
  (32×32 transparent; open state = active colour + filled icon; a dot
  badge appends " - New activity" to the aria-label), the **···** button
  (not rendered when its list is empty), and a close X (search preview
  only).
- ··· menu order (`Fe`): (1) a group labelled "Sidepane Features" with
  context buttons that did not fit (width-moved items, divider, items
  beyond the limit, divider, pinned items — no divider after the group
  when it only holds width-moved items); (2) action items flagged
  `shouldRenderInOverflow` (Participants, Meeting details at narrow
  widths); (3) divider; (4) the conversation's own items. Menu: below,
  centred, `autoSize: height`, `data-tid="entity-header-overflow-menu"`.

### 7.3 Responsive (header container width, not the window)

Live: header 892 px wide (bucket 834) in a 1280 px window.

| width | effect |
|---|---|
| header < 640 | Tabs move **under the title** (column; needs a title and `allowTabsToMoveUnderTitleAtSmallWidths`, default true; `forceTabsUnderTitle` forces it). Without a title tabs stay inline with 5 px start padding |
| header < 640 | Tab list becomes a **dropdown**: a small button with the active tab's name (`tab-overflow-button`); radio menu = predefined tabs, divider, other tabs, "Add a tab"; the active tab's submenu becomes a split item (`isDropdownAtSmallViewports`, default true) |
| header ≥ 640 / 480–639 / < 480 | Context-area buttons inline: **3** (`entityHeaderContextAreaLimit`) / 2 / 0; the rest go to "Sidepane Features". An **open** pane's button never overflows (it replaces the last visible one) |
| header < 640 | Chat: **Meeting details** moves into ···; the chat description hides when tabs are present |
| header < 720 | Chat roster count moves into ··· as **"Participants ›"** (`enableRosterSeparation`, live on); its popover anchors on ··· |
| header ≥ 834 | Group **Meet now** shows its text (below: icon only, tooltip "Meet now"); live roster avatars during a call only ≥ 834 |
| slot ≥ 480 | "External" badge shows text; below, icon only |
| experience container ≥ 768 | Tab max width `15rem`, else `7rem` (`enableResponsiveFwDeprecation`, live on) |
| window ≥ 1350 | An info pane in state "hidden" counts as open (filled icon, "Close …" label) |

**Measured live** (winpc, the "OST calendar test" meeting chat, window narrowed via VNC, 2026-11-07):
- **Header 781** (720–834): Join, the roster count, Meeting details, then the divider, Find, details and ···; tabs Chat then "+6".
- **Header 681** (640–720): as 781 without the roster count; Join sits 8 before Meeting details.
- **Header 604** (< 640):
  - the title is 14/700 (line 20) at y 10;
  - under it at y 28, `tab-overflow-button` shows the open tab ("Chat", 12/400 #424242) with a 12 px chevron 4 after it;
  - inline: Join, the divider, **Find only** at W−75, and ···;
  - the ··· menu (214 wide) reads: [Sidepane Features: **In this chat** `Alt+P` (chat details)], **Participants**, **Meeting details** | Open in new window `Ctrl+O` | Mark as unread, Move to section, Mute, Copy link | Report a concern.
- **Right-side layout**, packed from the right edge:
  - ··· at W−43;
  - the inline context buttons, 32 each;
  - a 16-wide divider;
  - the action items: the call container (the button plus 8), the roster count, Meeting details.
- **Tab overflow** is by width (Fluent overflow): the tabs that fit stay, the rest go under "+N" (14/400 #616161, padding 0 2, 60.3 tall).
  - Its menu sits 5 below and 5 in.
  - At 1280 the meeting chat showed Chat, Shared, Recap, then "+4".

### 7.4 1:1 chat

- Title: `h2[data-tid="chat-title"]` with the person's name, avatar with
  presence. **No rename pencil.** Optional "Nearby, in {{buildingName}}"
  badge (`enableNearbyInOneOnOneChat`).
- Action area order: External/trust tag → recording indicator (in call)
  → call duration → live roster (≥ 834, in call) → **call control** →
  roster button.
- **Call control** (live flags `enableCallDropdownInChatHeader`,
  `enableCallToolbarInChatHeader`, `enableDropdownCallingButtons`,
  `enableChatHeaderCallingDropdownStickyL1Button` all on): **one sticky
  primary icon button** + chevron.
  - Primary: **Audio call** (`default-chat-call-audio-button`) by
    default, or **Video call** (`default-chat-call-video-button`) when
    the remembered choice is video. The choice is
    `chat.oneOnOneChatHeaderCallButtonValue` (default `VOICE_CALL`);
    every call saves `updateUserPreferences(category:"userPersonalSettings", value:{chatSettings:{mruChatHeaderCallOption:"VIDEO_CALL"|"VOICE_CALL"}})`.
  - Chevron (`dropdown-calling-toggle-more-options-btn`, tooltip **"More
    call options"**; opening it looks up the other user's phone
    numbers): **Video call**, **Audio call**, delegate items (lazy),
    then **Audio call ‹mobile›** / **Audio call ‹work›** when PSTN is
    allowed and the number exists.
  - Hidden when: the user is blocked, a member is TFL off-network or
    an unverified SMS user, a bot chat without calling, a write-locked
    thread, or the only member is me. Click → `fireCallingIntent`.
- **Measured live** (winpc, 1280 wide, 2026-11-07):
  - the primary button (24 × 31.3, padding 5) sits at W−199 and the chevron (24 × 31.3, padding 7, 16 px icon) at W−175; the roster button follows at W−151;
  - the chevron's menu is 171.8 wide, 4.9 below the button, ending 4.6 left of the chevron's right edge;
  - its items: **Video call** `Alt+Shift+V` (`chat-call-video-button`) and **Audio call** `Alt+Shift+A` (`chat-call-audio-button`).
- **The remembered choice** lives in the user property `userPersonalSettings` (a JSON string), written by `PUT /v1/users/ME/properties?name=userPersonalSettings` with `{"userPersonalSettings": "<json>"}`:
  - Teams' value is `{"chatSettings":{"mruChatHeaderCallOption":"VIDEO_CALL"}}`, merged with the other settings, and written only when the choice changes (944031);
  - written from OST, winpc's Teams showed **Video call** after switching chats.
- **A Video call** offers the camera line `sendrecv` from the start, and the callee gets video as soon as they answer. With `recvonly` plus a later camera start, Teams shows only the avatar.
- Roster: icon button `chat-add-members` (PeopleAdd), tooltip **"Start
  a group chat"** (opens add-people, no count).
- Context area (only while the **Chat** tab is selected): **Copilot**
  ("Open Copilot"/"Close Copilot", with licence), **Agents and bots**,
  **Find in chat** (`enableChatInfoPaneSearch`), **Chat details**
  ("Open chat details"/"Close chat details", `enableChatInfoPane`,
  PanelRightExpand/Contract icon).
- ··· (**"More chat options"**, `chat-header-more-menu-trigger`; groups
  separated by dividers, empty groups dropped):
  1. **View Copilot history** (licence);
  2. **Open in new window** (`enableChatsPopout` &&
     `enableChatPopoutInContextMenu`, not in a pop-out window);
  3. **Schedule meeting** (member, not bot/SMS/write-locked);
     **Share screen** (allowed, member, not meeting/bot; disabled while
     a call exists for the chat);
  4. Mark as read / unread; **Move to ▸** / **Remove from section**
     (simple-collab mode replaces Pin); **Mute** / **Unmute**
     (`setMuteChat`); **Share app** (bot 1:1); **Copy link** (copies
     `{origin}/l/chat/{encodeURIComponent(id)}/conversations?context={"contextType":"chat"}`
     as rich text named after the chat; toast "Copied to clipboard");
  5. Report a concern (`enableChatRAC`, off live); **Delete** →
     `deleteChat`; in simple-collab mode labelled **"Remove chat
     history"**.

### 7.5 Group chat

- Title: topic, or the generated member list (`fitTitleWidth` when no
  topic).
- **Rename pencil** (`chat-title-name-group-chat`, tooltip **"Name group
  chat"**, filled while open) only when all hold: not 1:1, not meeting,
  not lie, not a Backroom meeting chat, user is a member, not the
  simplified flyout chat, chat policy not Disabled, not a TFL guardian
  chat, not an invite chat in AcceptPending.
- Rename popover: below the title (offset 0/9), 40rem wide, focus
  trapped; field **"Group name"**, placeholder **"Type a group name"**;
  **Cancel** / **Save**. Errors: > 250 chars → **"Your group name can't
  be longer than 250 characters."**; contains ":" → **"':' is not a
  valid character in group names."** Save → `setConversationTitle(convId,
  title.trim())` → **`PUT {chatsvc}/v1/threads/{id}/properties?name=topic`**
  body `{"topic": title}`; announcement "Group name was succesfully
  updated." (sic).
- Call control: idle + `enableGroupChatAudioDropin` + member → **"Meet
  now"** (`audio-drop-in-button`, video icon) + chevron ("More call
  options") whose menu has only **"Audio call"**. Above 20 members
  disabled: "Calls aren't available in chats with more than
  {{groupChatRosterSizeLimit}} people". In a call: Join / live roster.
- Roster count (`chat-header-participant-count`): 32 px high, min 28 px,
  bold 12 px count of members (minus TFL off-network); icon PeopleAdd
  for members, People otherwise; tooltip **"View and add
  participants"** (member), **"Add people and agents"** (with
  `enableCopilotInChatRoster`), **"View participants"**; aria
  "{label}, # participants". Below 720 px → ··· "Participants ›".
- Context area: as 1:1.
- ···: as 1:1, plus **Manage notifications ▸** (member, granular chat
  notifications on — then Mute is not offered), **Leave** (member and ≥ 3
  members; leave dialog), **Delete** (in simple-collab mode only when
  not a member or ≤ 2 members).

### 7.6 Meeting chat

- Title: meeting subject; recurring icon when recurring. **No pencil.**
- Action area: recording indicator → duration → live roster (≥ 834) →
  **Join** (primary, `chat-join-button`; hidden when cancelled; disabled
  while in that call) → roster count → **Meeting details** (tooltip
  "Meeting details"; needs `iCalUid`, not cancelled; inline ≥ 640 px,
  else in ···; opens `calendar.meetingDetails`).
- Tabs (worker `Ct`): Chat, Shared, Recap (recap exists), Attendance
  (report exists), Q&A (scheduled + flag), Meeting Whiteboard,
  Transcript / Recordings & Transcripts, Breakout Rooms (organizer),
  Speaker coach. Not Notes.
- **Measured live** (winpc, "OST calendar test" meeting chat, 2026-11-07):
  - **Join**: `chat-join-button`, 43.1 × 31.3 at W−238.3, brand fill, padding 5 8, 14/600 white, radius 4, 8 before the roster count;
  - roster count at W−187.2 (32.2 wide);
  - **Meeting details**: `chat-meeting-details`, 32 × 31.3 at W−155, TextBulletList icon;
  - then the divider, Find, chat details and ··· as in group chats;
  - tabs: Chat, Shared and Recap, then `tab-overflow-button` "+4" ("4 more tabs.", 21 wide) opening Attendance, Breakout Rooms, Q&A and Meeting Whiteboard, then Add a tab.
- **Where the data comes from.** `GET /v1/threads/{id}` → `properties.meeting` (a JSON string) has `subject`, `startTime`, `endTime`, `iCalUid`, `isCancelled`, `organizerId` and `meetingJoinUrl`. The conversation list doesn't carry it.
- **Empty chats.** A chat nothing has been said in (`properties.isemptyconversation` "True", e.g. a new meeting's chat) isn't in Teams' chat list. It appeared on winpc after the first message.
- ···: as group, with **Report a concern** in its own group (policy
  `reportMeeting == "ENABLED"`, `enableReportMeeting`, not TFL), and
  **Leave**/**Delete** only when the user is not the meeting creator.

### 7.7 Channel

- Title `h2[data-tid="channelTitle-text"]` 18 px bold ("General"
  localised); team avatar 32×32 (`channel-title-avatar`); hover opens the
  channel card. **No pencil** (rename is Edit channel in ···).
- Action area order: Join channel → tab-conversation button → NGC icon →
  sensitivity label → audience (not in General unless
  `enableGeneralChannelAudienceAwareness`) → **Meet now**.
- **Meet now**: transparent button `channel-meet-header-main-btn` (video
  icon + text **"Meet now"**, 97×32 live) + chevron
  `header-meeting-more-options` (20×32, tooltip **"More channel meeting
  options"**) → **Meet now**, **Schedule a meeting** ("View meetings"
  only with a flag, unset). The chevron shows only if an item is
  enabled. Meet now not allowed but scheduling allowed → the main button
  becomes "Schedule a meeting". Disabled tooltips: "Join the channel to
  start or schedule meetings", "Only moderators can start or schedule
  meetings". The text is dropped with `enableTabsPlusPlus` or
  `enableCoreVisualRefresh`.
- Context area (only while **Posts**/Conversation is selected): thread
  list (conversational channels), Copilot, **Find in channel**
  (`channel-search-toggle-button`), **Agents and bots** (standard
  channels), **Channel details** ("Open channel details"/"Close channel
  details"), meetings toggle (flag).
- ··· (**"More channel options"**, `more-apps-button-tid`), module 82632
  with `entryPoint: ChannelHeader` (close to, but not the same code as,
  the left-rail channel menu in §5.5):
  1. "See new posts at bottom/top" (post channels with reverse scroll);
  2. **Open in new window**;
  3. Channel notifications / Manage notifications ▸, Move to ▸,
     Pin/Unpin, Show/Hide, Join channel;
  4. Add members / Add people / Share channel ▸, Edit channel, Manage
     channel, Manage tags, **Copy link** (else Get link to channel),
     recommend, Get email address, Connectors, Workflows;
  5. Leave channel, Archive/Restore channel, Delete channel, Remove from
     team.
  → TODO: the live render (the menu could not be opened).

### 7.7.0 See new posts at top (measured 2026-11-09)

Turning it on writes the user property `enableChannelsV2` "false" (it is
"true" for new posts at the bottom). Posts are then newest activity first,
under Teams' collapsed composer (`post-compose-collapsed`):
- the post cards' width, 15 under the header, 108 tall, radius 6, shadow
  0 0 2 / 0 2 4;
- your avatar (32, presence) at (16, 12), and the **Post in channel**
  button (14/20 semibold #424242, 31.3 tall) from 46;
- the post types 68 down: **Post** (96 × 30, #EBEBEB, brand text and the
  channel icon) and **Announcement** (147.5 × 30, white, megaphone) at
  123.5.

The first post is 32 under the card. The composer opens in the card's
place, and Announcement opens it as an announcement.

### 7.7.1 Manage channel (measured 2026-11-09)

Opened from either channel menu's **Manage channel**; it takes the
conversation's place while the channel stays selected in the list (picking
the channel again, or **Go to channel**, returns to its posts).

- Header 61 (white, a #E0E0E0 0.67 line, padding 0 7 0 20): team picture
  32 (radius 4) 14.2 down; channel 18/24 bold at 60; tabs **Settings** and
  **Analytics** 2 after it (buttons 56.3 tall, 8 each side of the 14/20
  name, #424242 / 600 #242424 with a 3 px brand pill under the name);
  **More options** (32 × 24, 39 from the right, 18.2 down): Go to channel,
  Open in new window | Manage notifications ▸, Move to section ▸, Hide |
  Edit channel, Manage channel, Copy link, Get email address (no
  Workflows), the menu's right edge on the button's, its top at its
  bottom.
- **Settings**: sections 48 from both sides, from 20 down. Each header row
  is 44 tall (padding 0 12 0 10, a 20 px chevron, the name 14/20 semibold at
  38, its hint 30 after in #616161), a #E0E0E0 line after the open body
  (13 under it).
  - **Channel details** — "Edit channel name, description, and layout": the
    name 28/36 semibold, the layout pill (Posts / Threads; 14/20 #616161 on
    #E6E6E6, a #D1D1D1 line, radius 4, padding 2 8) 66 down, **Edit** (brand
    96 × 31.3) 106.3 down opening Edit channel.
  - **Moderation** — "Set channel moderation preferences" (General):
    "General Channel:" then **Anyone can post messages**, **Anyone can post;
    show alert that posting will notify everyone (recommended for large
    teams)**, **Only owners can post messages** (radios 16 in 32 boxes, names
    14/20 at 36, max 496 wide, rows 32 apart plus wrapping). Picking one
    writes the team thread's `spaceAdminSettings` back whole with
    `userSettings.generalChannelSetting` 0 / 1 / 2:
    `PUT {chatsvc}/v1/threads/{teamThread}/properties?name=spaceAdminSettings`
    `{"spaceAdminSettings": "<json>"}`.
  - **Moderation** for any other channel (body offsets from its top, 38 in):
    "Channel moderation" (12/16) and a filled-darker dropdown 26 down
    (355 × 31.3, #F5F5F5, radius 4, the value 14/20 semibold at 12; its list
    2 under it, 355 wide, padding 4, 32 tall rows 2 apart with the names at
    32, the chosen one bold): **On** / **Off**.
    - Off: "Who can start a new post?" 72.4 down, then radios **Everyone can
      start a new post** / **Everyone except guests can start a new post**
      (32 apart from 98.4); the line after it 182.4 under the body's top.
    - On: "Who are the moderators?" 72.4 down; who (14/20 brand) 104.7 down:
      Team owners (Channel owners for private/shared channels) and up to two
      added moderators (15 letters then "..."), "+ N" for the rest; hovering
      it shows a card above (padding 16 0; group names 12/16 at 12; people
      32 px pictures at 10.7 with names 12/16 at 47.7; a name opens a chat).
      **Manage** (brand 96 × 31.3) 260 in, 98.4 down. "Who can start a new
      post?" 144.7, "Only moderators" (14/20) 170.7, **Team member
      permissions** (Channel member… in private/shared; 14/20 semibold)
      205.7 and checkboxes 42 apart from 235.7: Allow members to reply to
      channel messages, Allow members to pin channel messages, Allow bots to
      submit channel messages (connectors are off in Teams' build).
    - Only team owners (and moderators) can change it; otherwise disabled.
    - Wire: the channel thread's `channelSettings`, numbers in Teams' key
      order: `PUT {chatsvc}/v1/threads/{channel}/properties?name=channelSettings`
      `{"channelSettings": "{\"allowReplies\":0,\"allowPinPosts\":0,\"allowBotsPost\":1,\"allowConnectorsPost\":1,\"postPermissions\":1}"}`.
      postPermissions 0 everyone, 1 moderators, 2 everyone but guests;
      allowReplies / allowPinPosts 0 everyone, 1 moderators; bots /
      connectors 1 allowed. The dropdown writes Teams' defaults with only the
      post permission changed; radios and checkboxes change one field of
      the current settings. Read from `GET {chatsvc}/v1/threads/{channel}`
      (`properties.channelSettings`; unset = defaults).
    - Moderators: `GET …/threads/{channel}/members?view=msnp24Equivalent&pageSize=100&filterOnIsModerator=true`;
      owners: the team thread's members with `selectMemberRoles=Admin`.
  - **Add or remove moderators** (Manage): 600 × 600, padding 24, radius 8;
    title 20/28 bold; search box 52 under it (546 × 32, white, #D1D1D1
    hairline, a darker bottom line, brand underline focused, "Type a name of
    a person"); its matches 2 under it (546, padding 4; "We didn't find any
    matches"); the list 44 under the box (532 wide, 48.3 rows with #E0E0E0
    lines: "Team owners / {n} people" with the people-team picture, then each
    moderator with e-mail and Remove); "Moderator capability is not audited."
    (12) and Cancel / Done (96 × 31.3, 10 apart) along the bottom. Search:
    `POST {userProfileService}/api/v1.0/teams/{teamThread}/users/profilesearch?top=100&includeDLs=false&includeBots=false&enableGuest=false`
    `{"keyword": "…"}` (middle-tier token; owners and listed moderators left
    out; the second line "(ALIAS) job title"). Done: `PUT
    {chatsvc}/v1/threads/{channel}/members` `{"members": [{id, isModerator:
    true, expiration: 0} | {id, isModerator: false}]}`; a failure shows Teams'
    toast ("There was an error adding moderators." / "…removing…" /
    "…adding or removing…").
- **Analytics** (channel-dashboard): "Select a channel" (All Channels +
  the team's channels; All Channels opens the team's analytics) and "Time
  period" (Last Seven / Thirty / Ninety Days), two 31.3 dropdowns 10 apart
  at 30 in, 50 down; the period's dates ("10/30/2026 - 11/5/2026",
  semibold, 35 tall); **Analytics across channels** (brand) under them at
  the right. Cards (#FAFAFA, radius 4, padding 12, the title 14/20 bold
  26 down) from 152.7 down, 20 in: Summary (Active users, Meetings) and
  Engagement (Posts, Replies, Reactions, Mentions) side by side (28/36 over
  14/20, spread), then Active users (spline), Meetings (columns) and
  Engagement (stacked columns, legend) full width; "No Data Available"
  centred 82 down when empty. Charts are min(40 % of the window, 300) tall
  (Highcharts: plot 10 from the top/right, 37 under it for dates, 75 with
  the legend; y 0 to ≥ 10 in whole ticks ~72 px apart; grid #E8EBFA; the
  axis #CCD6EB; colours brand, lighter brand, #9092C1, #242424).
  Data: `GET {mt}/beta/analytics/teams/{groupId}/channels/{channel}/summary-timeseries?metric=all&timeperiod=last-seven-days&includeTimeseries=activeUsers%2CpostMessages%2CreplyMessages%2Creactions%2Cmentions%2CmeetingsOrganized`
  (`x-ms-client-caller: tca-pc`) → `{channels: {metrics: {name: {value,
  timeSeries: [{value, date}]}}}, startDate, endDate, errorCode}`; errorCode
  2 means no data, any other code shows "We are sorry - We've run into an
  issue".

### 7.8 Non-default tab selected

- Chat: Copilot, Find in chat, Chat details and notes disappear unless
  the Chat tab is selected; calls, roster and ··· do not change.
- Channel: Find and Channel details disappear unless Posts is selected.
  For an **ExtensionTab/WebsiteTab** (`tab:` id, `canHaveTabConversation`
  not false) a **`btn-tab-conversation`** button appears in the action
  area: **"Show tab conversation"** / **"Hide tab conversation"**,
  disabled "Setting up conversation..." while pending. Live with the
  **Page** tab selected: only Meet now, its chevron, the divider and ···.
- An **expanded** tab hides the whole header (`display:none`).

### 7.9 Built-in chat tabs (worker `Ct`, `tabsConnection`)

| tab | rule |
|---|---|
| **Chat** | always ("Everyone Chat" for comment streams, "Activity" for notification-only bots) |
| **Shared** | `enableChatFilesTab && enableChatSharedTab` (both on), SPO upload not disabled, bots only with file support ("Files" when the Shared flag is off) |
| **Recap** | meetings with a recap, **and** any non-bot `chatType == "Chat"` when `showRecapTabForAdhocChat` (live on) |
| **Notes** | `enableFluidThread && enableFluidThreadAsTab`; internal, non-meeting, non-federated, same-tenant, non-guest |
| **Storyline** | 1:1 with Engage/Storyline flags |
| **Photos** | `enablePhotosTab` (off) |

### 7.9a Group chat header, measured live (winpc, 2026-11-07)
- The header is 61 tall, white, with a 0.67 px #E0E0E0 bottom border.
- Left to right:
  - the 32 px avatar at (20, 14.2) (`tfw-group-chat-avatar-button`, "Change the group profile picture", with a 12 px camera icon);
  - the title (18/25.7, weight 700) at 62;
  - the rename pencil (21.3) 4 after the title;
  - the tabs Chat, Shared, Notes, Recap and "Add a tab" (no Storyline in group chats).
- The toolbar (`entity-header-toolbar`) holds:
  - Meet now (`audio-drop-in-button`, 101.8 × 32, video icon plus "Meet now" 14 semibold #424242) and its chevron (28 × 36);
  - the participant count (32.2 × 32, PeopleAdd plus a bold 12 px count, aria "View and add participants, 2 participants");
  - Find in chat, Open chat details, and More chat options (32 each).
- More chat options (214 wide): Open in new window (Ctrl+O) | Schedule meeting, Share screen (Ctrl+Shift+E) | Mark as unread, Move to section ▸, Mute, Copy link | Remove chat history.
- Rename goes through `PUT /v1/threads/{id}/properties?name=topic` with `{"topic": …}`, verified from OST; the chat list picks up the new name.

### 7.9b A call going on in a group chat (winpc and Teams web, 2026-11-07)
- **Where Teams learns of it.** The thread property `awareness_conversationLiveState:<messageId>` (`:0` in group chats) is a JSON string:
  - fields: `conversationUrl`, `conversationId` (the call id), `groupCallInitiator` (MRI), `groupCallInitiatorDisplayName`, `expiration` (seconds), `status` (`Active`), `callStartTime`, `conversationType` (`huddleGroupCall` for Meet now), `isHostless`, `meetingInfo`;
  - it comes with the conversation list (`threadProperties`), so the chat list knows without loading messages;
  - 527114 `getCallInfo` / `hasActiveCall` treat it as live while `expiration` hasn't passed.
- **The header pill** replaces Meet now (`chat-calling-meeting-buttons`, 126.4 × 34 with Join):
  - frame: 1 px padding on a `linear-gradient(262.62deg, #3EB0F0 19.93%, #AB9EFF 43.11%, #2200FF 67.75%, #AD00FF 100%)`, radius 6, shadow `0 0 2px rgba(0,0,0,.12)`;
  - live roster (`audio-drop-in-live-roster-button`, "View participants"): white, radius 4 0 0 4, padding 4 6; the filled sound-wave icon (20, brand #5B5FC7) at 6, then `participants-live-roster-list` at 32;
  - avatars: 24 px, each with `margin-right: -10px` (14 apart), at most 5 (`maxVisibleParticipants`), then a "+N" avatar;
  - one avatar: 62 wide; two: 76;
  - divider: 0.67 × 32, NeutralStroke1 (#D1D1D1);
  - **Join** (`audio-drop-in-join-button`): 45.7 × 32, radius 0 4 4 0, padding 6 10, "Join" 14/600 #242424 on white;
  - in the call, only the live roster shows.
- **The chat list row** shows the regular sound-wave icon (14, NeutralForeground3) at (244, 9) in the 288 × 32 row. It sits beside the unread dot when both apply.
- **Timeline rows.** Start events name the initiator only by MRI (`<name>8:orgid:…</name>`, no display name). Teams shows "{name} started a meeting." with the name from the roster.
- **Joining** goes through `POST epconv` with `groupChat {threadId, messageId: null}`, no `to`, `suppressDialout: true`:
  - the service puts you in the thread's live conversation; the response's `roster` lists who is already there;
  - about 8 s later the mixer re-offers (`mediaRenegotiation`, `fromMixer: true`, an added `x-data` m-line) with content type `application/sdp-ngc-1.0`;
  - the answer must carry the same content type, or the call ends with 410/301029 "AnswerContentTypeNotConsistent".
- **Toast** (527114 `uMe`): someone else's Meet now arrives as a call-manager push (evt 128, gzipped `cp`) with `notificationType: "HuddleMeetingStart"`, the liveness fields, `threadId` and `messageId` "0".
  - Content: the chat topic (else "(No title)"), the subtitle "{{audioDropInCaller}} started a meeting" (name fallback "Someone"), and the buttons **Join** (`calling_nudge_button_join`) and **Message** (`calling_meeting_started_secondary_button`).
  - It is dropped when the type or call id is missing, for a duplicate call id, when the user setting is off, when the chat is muted, and when you're already in that call.

### 7.9c Who is in a chat's call when you aren't in it (2026-11-08, verified live)
- **Subscription.** Teams watches the open chat's call without joining (calling-pluginless `subscribeToCall`):
  - It POSTs a conversation request to the liveness entry's `conversationUrl` (the flight-proxied conv service): `conversationRequest` with `roster: {type: "Delta", rosterUpdate}`, `properties` and `links` (conversationEnd, conversationUpdate, localParticipantUpdate, addParticipantSuccess/Failure, receiveMessage), plus `groupChat {threadId, messageId}`, `participants.from`, the capabilities, `endpointMetadata` and `endpointState`.
  - There is no `callInvitation`. The answer is 200 `application/vnd.skype.gvc.v1.0+json` with the roster.
  - Roster deltas then come to the `rosterUpdate` link; Teams web also opens a broker channel.
- **OST:**
  - `calling::live_roster` subscribes with callbacks under `subscription/…`, kept apart from the call you're in. It follows the deltas and leaves the conversation when the chat changes.
  - The header shows everyone in the call besides you.
- **Meeting band** (`chat-live-roster`, winpc):
  - After the duration (12 px white) comes a 7 px gap, then 32 px avatars every 22 px (they overlap by 10; the row's 10 px right padding takes the last one's overhang), then 8 px to Join.
  - At most 5, then +N. Shown from 834 px wide.
- **Group call pill:** its 24 px avatars come from the same roster (before, it showed only who started the call).

### 7.10 Header TODOs
- Live 1:1, group and meeting headers (code + live flags only so far).
- Labels for header Mark as read/unread (708158) and Manage
  notifications (873861); worker endpoints for mute, pin, hide, delete,
  leave; the delete confirmation dialog; `PopoutConv` shortcut text.

## OST status against this spec
- [ ] List width 280/320/360 px by window width (<640 hidden), drag-resize clamped 280–400, double-click reset.
- [ ] Header: title by mode; ··· menu items and order (Mark all as read split item with All / All chats / All channels / All communities; Collapse all sections; Customize view with Try it badge; Your teams and channels; Your communities).
- [ ] Mark all as read from the menu without confirmation; Shift+Esc with the confirmation dialog and "Don't ask again".
- [ ] Collapse all sections saves expanded state on the server.
- [ ] Filter toggle labels, Ctrl+Shift+F, text box placeholder by mode, 100-char limit, 250 ms debounce, Esc closes, empty-result state.
- [ ] New message button + New items ▾ split; menu items, order, dividers and their conditions.
- [x] Sections from `conversationFolders` in server order with their expanded state (Quick views, Favorites, your sections, Chats, Teams and channels, Communities). Still to come (TASK-0075): the Copilot row, See more paging, and the Followed threads / Saved quick views.
- [ ] Section ··· menu per section type; create / rename / remove section dialogs; emoji icons.
- [x] Filter pills in config order (Unread, Channels, Chats, Meeting chats, Communities); single-select categories; Unread combinable; width-based overflow with More filters / Fewer filters second row; selected pills stay visible; "You're all caught up!" with Clear filters.
- [ ] Bold only when unread and not an expanded branch; brand badge dot for unread unmuted chats; number badges on sections/teams; meeting/huddle and followed charms.
- [x] "New" badge on new teams and never-opened channels (CSA team list: no read horizon).
- [ ] Hidden chats rules (hide until a newer message; declined meeting chats); temp hoist of a selected hidden item.
- [ ] Chat ··· menu order and per-type rules. Done: Mark as read/unread, Move to section ▸, Remove from section, Mute, Copy link, Leave (≥ 3 members, not a meeting chat you created), Hide/Unhide (`unpinnedTime` + `historyHiddenTime`; null to unhide). TASK-0075: Open in new window, Notify when available, Manage apps, Set workflows, Remove chat history.
- [ ] Channel ··· menu and team ··· menu order and rules.
- [ ] Drag and drop of sections, items and teams; Start reordering.
- [ ] Shortcuts in §6.
- [ ] Header layout: 61 px, title 18 px bold, toolbar order action items › divider › context buttons › ···.
- [ ] Header breakpoints on the header's own width (ResizeObserver): <640 tabs under title + dropdown, Meeting details into ···; <720 Participants into ···; ≥834 Meet now text; context buttons 3/2/0 at ≥640/480–639/<480, overflow into a "Sidepane Features" group at the top of ···.
- [x] 1:1 call control: one sticky Audio/Video button (last used, saved to `mruChatHeaderCallOption`) + "More call options" chevron.
- [x] Group chat: Meet now (video icon) + chevron with only Audio call; roster count button with its tooltips.
- [x] Meeting chat: Join and Meeting details (inline from 640, else in ···; opens the meeting in the calendar, its week then its card); meeting tabs; Leave hidden for the creator.
- [ ] Rename pencil only for group chats (member, not policy-disabled); popover with 250-char and ':' rules; PUT thread property `topic`.
- [ ] Channel: Meet now split button (Meet now / Schedule a meeting) with its disabled reasons; Find / Channel details only on Posts; Show/Hide tab conversation on Extension/Website tabs.
- [ ] Chat and channel header ··· menus per §7.4–7.7.

## People flyout and Add people (measured on winpc, 2026-11-07, OST group test)
- **Flyout.** 251.3 wide, white, radius 4.
  - Header: "People (n)" 12/16 semibold #616161 at (15.7, 17.7).
  - Member rows: 242 × 48 from (6.7, 37.7), hover #F5F5F5, a tooltip with the name. Each has a 32 px avatar with presence at 12 in, and the name 14/20 at 54 in: 5 down with "You" (12/16) at 25 for you, 13 down otherwise.
  - Then a #E0E0E0 divider (16.7, 218 wide) and Add people (`chat-add-members`, 246 × 31.3; person-add-20 at 24.3, label at 60.3).
  - Then Add agents (`add-copilots-btn`), which OST doesn't have yet. The flyout ends 16.7 below the last row.
- **Add dialog** (`chat-add-participant-popup`). 402 wide, 16.7 padding.
  - "Add" (14/20 #424242).
  - The people picker at 43.3, placeholder "Enter a name, email, or tag" (the same TagPicker as Share contact).
  - Three radios (12 px, 20 apart): "Don't include chat history" (default), "Include history from the past number of days:" with a days box (1 to 999, default 1), and "Include all chat history". The chosen label is #242424, the others #616161.
  - Cancel and Add (96 × 31.3) at (185.3 / 289.3, 160). Add is disabled until someone is picked.
- **Request** (r_data-resolvers-chat `addMembersToConversation` → services-chat `ln` → 534565 `ke`). `PUT {chatsvc}/v1/threads/{id}/members` with `{"members":[{"id":mri,"role":"Admin","shareHistoryTime":t}]}`, where t is −1 for no history, 0 for all of it, or now − days × 86 400 000. Remove is `DELETE /v1/threads/{id}/members/{mri}`.
- **Remove.**
  - Hovering another member's row shows an X (`chat-header-remove-user-button`, 32 px, transparent, tooltip "Remove") about 30 in from the flyout's right edge.
  - The X opens `remove-user-dialog`: 600 × 144.7, radius 8; title "Remove {name} from the conversation?" (20/28 semibold at 24.7), "They'll still have access to the chat history." at 59.3, and Cancel and Remove (96 × 31.3) at 88.7.
  - With more than two people, the flyout also offers Leave.
  - Every member shows presence, including Offline.
- **Verified live (2026-11-07).**
  - OST added randy@techit.pw to OST group test and then removed it. Teams web showed "OST Test 1 added Randy Northrup to the chat and shared chat history from the past 2 days." and "OST Test 1 removed Randy Northrup from the chat."
  - The server moved the shared-history time to the chat's oldest message (about 2.2 days back, though 3 days were asked for). Teams rounds that to days.
