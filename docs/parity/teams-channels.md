# Teams & Channels: functional parity checklist (new Teams desktop for Windows, 2025-2026)

Scope: the unified Chat + Teams-and-channels list, the separate Teams view, "Your teams and channels" page, join/create team, team management, channel types, channel menus, layouts (Posts vs Threads), posting, tabs, files, meetings, tags, mentions, notifications, archive/delete/restore.

Conventions: `- [ ]` = feature to implement. Exact UI strings are in **bold** or "quotes". "Graph:" lines name documented Microsoft Graph endpoints/properties. Items marked **[unverified]** were not confirmed in a fetched Microsoft document during this research pass and should be checked against the live client (winpc).

---

## 1. Chat list shell: combined vs separate view

- [ ] Combined view (default): the **Chat** app on the app bar holds chats, teams and channels in one list with three built-in sections in this order: **Favorites** (pinned items imported here), **Chats** (sorted by recency, shows up to 25 chats with an option to see more), **Teams and channels** (channels you've chosen to show, grouped by team).
  Source: https://adoption.microsoft.com/files/microsoft-teams/chat-and-channels/Teams-new-chat-and-channels-user-guide.pdf (p.2) ; https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Separate view: Chat app (icon "Teams Chat Tab icon") and a separate **Teams** app (three-people icon) on the app bar; each has two sections: Favorites + either chats or channels. Filters, @Mentions view, custom sections, New message and Go to still work in separate view (@Mentions only shows results for that app's half).
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912 ; user guide PDF p.9
- [ ] Switch views: chat-list header **More list options** (…) > **Customize view** > **Combined** / **Separate**. Also in **Settings and more** (…) > **Settings** > **Chats and channels** > "Viewing chats and channels" with Combined/Separate picture radio cards.
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912 ; user guide PDF p.2-4
- [ ] **More list options** (…) menu on the list header contains (desktop): **Mark all as read** (with › submenu), **Collapse all sections** (shortcut Alt+Q), **Customize view** (with "Try it" badge during rollout), separator, **Your teams and channels**.
  Source: user guide PDF p.2 (screenshot)
- [ ] First-run "A streamlined experience for chats, teams, and channels is here" dialog with **Do it later** / **Get started**; "Do it later" re-prompts about daily up to three times, then a final forced "Get started" screen ~a week later. (Optional for a clone; only if migration flow is emulated.)
  Source: user guide PDF p.1
- [ ] List header icons (left to right): **More list options** (…), search/filter (magnifier) toggles an inline text filter box, **New items** (compose icon with ▾).
  Source: user guide PDF p.2, p.6-7 (screenshots)
- [ ] **New items** ▾ menu items: **New message**, **New channel**, (tenant-dependent "New storyline post"), separator, **Join team**, **New team**, separator, **New section**.
  Source: user guide PDF p.4 ; https://adoption.microsoft.com/files/microsoft-teams/Threads-layout-in-Microsoft-Teams-channels.pdf (p.2 screenshot)
- [ ] Keyboard: **Ctrl+N** starts a new message to a chat *or a channel* (the compose "To" picker searches people, chats and channels); **Ctrl+G** "go to" mode in the title-bar search box ("Type a chat or channel") jumps to a chat/channel by participant or channel name.
  Source: user guide PDF p.8-9
- [ ] Settings > **Chats and channels** page (desktop): "Viewing chats and channels" (Combined/Separate); "Chats and channels list": **Show message previews for chats and team names for channels** (On/Off; default Off on desktop, On on mobile), **Show time stamps**; **Hide inactive channels** ("Periodically hide channels you haven't checked in a while", toggle + **Hide now** button; newer label "Suggestions for hiding inactive channels … Get suggestions now"); **When I go to a channel, show recent activity**: **At the top** / **At the bottom**; "Threads" group: **Automatically follow threads in threaded layout channels** (checkboxes **Threads started from my messages**, **Threads I'm part of**, **Threads where I'm @mentioned**) and **Automatically follow threads in post layout channels** (**Replies to my posts**, **Replies I'm part of**, **Replies where I'm @mentioned**), with a link "Replies to followed threads and posts" to notification settings.
  Source: user guide PDF p.3-4 ; Threads PDF p.12 (Settings screenshot)
- [ ] Bold = unread: chat/channel names render bold on new activity; in combined view the **Teams and channels** quick-navigation bar (pinned at the bottom of the list) turns bold when any channel below is unread, even if not scrolled into view, and shows a red "@" for unread @mentions (and a meeting/camera glyph for live meetings). Clicking the bar scrolls to the Teams and channels section.
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912 ; user guide PDF p.3
- [ ] Channels show activity icons (dot/@) instead of numeric counts for personal/tag mentions (consistent with chats).
  Source: user guide PDF p.12 (FAQ 4)
- [ ] Collapsed sections still bold when they contain unread items and show "@" when there are new mentions.
  Source: user guide PDF p.5

## 2. Filters, Quick views, @Mentions, Followed threads

- [ ] Filter pills at the top of the list: **Unread**, **Channels**, **Chats** shown by default; **Meeting chats** and text-search filter behind the **More filters** chevron (˅/˄ expands a second row). **Unread** can be combined with one of Channels/Chats/Meeting chats. Filter state persists when you navigate away and return; click the pill again to clear. New updates still stream into a filtered list (Unread: new unread items appear as they arrive).
  Source: user guide PDF p.6-7 ; https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Quick views block at the top of the list (above Favorites): **Copilot**, **Discover**, **Mentions** (@Mentions view), **Followed threads**, **Tag mentions** (tag icon). Hover "Quick views" > **See more** (eye icon) to choose per item: **Always** / **When unread** / **Hide**. Drag items to reorder.
  Source: https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912 ; Threads PDF p.2-4 (screenshots)
- [ ] @Mentions view: a middle-column list of every personal @mention across chats, meeting chats and channels (including hidden channels), with an **Unread** pill; selecting an item opens the message in context in the right pane where you can react/reply.
  Source: user guide PDF p.7-8
- [ ] Tag mentions view: same pattern for tag @mentions in channels.
  Source: user guide PDF p.8 ; https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] Followed threads view: header "Followed threads (i)", **Unread** pill, … and search; each row shows channel avatar, channel name · "N replies", time, root-post preview and latest reply preview; ordered by time of most recent reply; bold = unread. Right pane shows the thread with a **Go to channel** button and a "Send to: thread only ▾" reply box. Includes followed post-layout conversations too.
  Source: Threads PDF p.10 ; https://practical365.com/teams-threaded-layout/
- [ ] Graph: no first-party Graph endpoint for followed threads / quick views (client-side state). **[unverified]**

## 3. Sections, favorites, sorting, ordering

- [ ] Favorites: a built-in custom section; add via item **More options** (…) > **Show in** > **Favorites** (older builds: **Pin** / **Unpin**). Pinned items from classic Teams are imported into Favorites.
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8 ; user guide PDF p.2
- [ ] Custom sections: **New items** > **New section** > name > **Create**. Up to **50 sections**, **50 conversations per section**. Can hold channels and 1:1/group/meeting chats. Add items by drag-and-drop or item context menu **Move to** / **Show in** > <section> (or "New section" inside the Move-to picker). A channel moved into a section is removed from under its team in Teams and channels; whole teams can't be added to a section.
  Source: user guide PDF p.4-5, p.12 ; https://support.microsoft.com/en-us/office/reorder-the-chat-and-channels-list-in-microsoft-teams-964d8358-53c3-4200-8cb1-5e9c5091031e
- [ ] Section header … menu (custom section): **Sort** group: **Custom** (default for Favorites/custom), **Most recent**, **Unread only**; then **Rename section**, **Remove section**. (Mobile also has "Mentions at top" toggle.) "Unread only" shows unread items plus a **See read** row.
  Source: user guide PDF p.5-6
- [ ] Default sort: Chats section and flat Channels list sorted **By recency**; hierarchical Teams and channels sorts channels **A-Z** within each team. Manual drag reorder only works when sort = Custom. Sections can be dragged to reorder (desktop). Reordering channels replaces the classic ability to reorder teams; if channels can't be reordered you can drag the team, which moves all its channels with it. New section dialog: name > **Create**; item … > **Move to** > section (or **New section**).
  Source: user guide PDF p.5, p.12 ; https://support.microsoft.com/en-us/office/reorder-the-chat-and-channels-list-in-microsoft-teams-964d8358-53c3-4200-8cb1-5e9c5091031e
- [ ] Teams and channels section label … menu: **List options** › **Teams and channels** (hierarchy, ✓ default) / **Channels only** (flat list, sortable **Most recent**; channels named "General" keep their team name as a suffix); **Hide inactive channels**; **Your teams and channels**.
  Source: user guide PDF p.11 ; https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Collapse/expand any section by clicking its header chevron; **Collapse all sections** (Alt+Q) from More list options.
  Source: user guide PDF p.2, p.5

## 4. Teams and channels section (tree) behavior

- [ ] Each team row: team avatar (picture or colored initials tile) + name, expandable; under it only the channels you've chosen to show, then a **See all channels** link (opens team's full channel list incl. hidden). Bottom of the section: **See all your teams** (combined) / **See all your teams and channels** (separate view).
  Source: user guide PDF p.10 ; https://support.microsoft.com/en-us/topic/d1036ef9-8295-41e4-848a-cb92e3431912
- [ ] Only teams with at least one shown channel appear. Teams that were "hidden" (classic) but have a shown channel appear collapsed at the bottom; the old **Hidden teams** section is gone. Teams with no shown channels aren't listed.
  Source: user guide PDF p.10
- [ ] Hide a whole team from the list via team **More options** (…) > **Hide all channels**. Hiding all channels of a team hides the team.
  Source: user guide PDF p.11 ; https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8
- [ ] Hidden channels still notify for @mentions, @tags, and replies to followed threads/posts.
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8
- [ ] Unread channel row: bold name + leading "•" bullet; red "@" glyph on the right for mention; private channel shows a lock icon; shared channel shows a shared (linked people) icon; archived channel shows an archived icon. **[icon glyphs: verify on winpc]**
  Source: user guide PDF p.10 (screenshot) ; https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://support.microsoft.com/en-us/teams/teams-channels/archive-or-restore-a-channel (via fetch summary)
- [ ] "Recommended"/auto-shown channels: a channel can be marked to show for every member by default (Graph `isFavoriteByDefault`; always shown for education and frontline users). Owners use Edit channel > **Recommend that people show this channel in their channel lists** (max 10).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0 ; https://support.microsoft.com/en-US/teams/teams-channels/edit-a-channel-in-microsoft-teams
- [ ] Graph: `GET /me/joinedTeams`; `GET /teams/{id}/allChannels` (hosted + incoming shared); `GET /teams/{id}/channels`; `GET /teams/{id}/incomingChannels`. Per-user show/hide/favorite/section state is not exposed by Graph **[unverified]**.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0

## 5. "Your teams and channels" page (See all your teams)

- [ ] Opened from **See all your teams** / **See all your teams and channels** at the bottom of the list, or **More list options** > **Your teams and channels**. Full-page view titled "Your teams" with tabs/filters including **All** and **Analytics**, a dropdown "Teams you own" / **Archived Teams** ("3 more" overflow dropdown), search by team name, and a **Create team** button (upper right).
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8 ; https://support.microsoft.com/office/dc161cfd-b328-440f-974b-5da5bd98b5a7 ; https://support.microsoft.com/en-us/topic/a90c30f3-9940-4897-ab5b-988e69e4cd9c
- [ ] Sort: **A-Z** or **Z-A**. Filters: **Teams with hidden channels**, **Teams with channels shown**, **Archived teams**, **Team type**, **Membership type**, **Visibility type**.
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8
- [ ] Select a team to see all its channels with a **Show** / hide control per channel; showing a channel also brings its team back into the list. (Mobile: tap circle to select/deselect.)
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8 ; user guide PDF p.10
- [ ] Each team row has a **More options** menu (same items as the team … menu, incl. **Archive team**, and **Restore team** for archived teams).
  Source: https://support.microsoft.com/office/dc161cfd-b328-440f-974b-5da5bd98b5a7
- [ ] **Analytics** tab across all teams: date range picker; columns active users, people, active guests, posts, replies, type (private shown with lock icon).
  Source: https://support.microsoft.com/office/5b8ad4b1-af34-4217-aff4-cd11a820b56b

## 6. Create a team

- [ ] Entry points: **New items** > **New team** (combined or separate); or Your teams page > **Create team**; separate view also "Create and join teams and channels" > **Create team**.
  Source: https://support.microsoft.com/office/174adf5f-846b-4780-b765-de1a0a737e2b ; https://support.microsoft.com/en-us/topic/a90c30f3-9940-4897-ab5b-988e69e4cd9c
- [ ] Create-team dialog (from scratch, single page): **Team name** (required), **Description** (optional; max 1,024 chars per Graph), **Team type**: **Private** ("limits content and conversation to a specific group") / **Public** ("anyone in the org can join"); **Sensitivity** label dropdown if org uses data classification (default label preselected; teams default to private if org allows); **Channel name** for the first channel (required; first channel's description = team description); **More create team options** link; **Create** / Cancel.
  Source: https://support.microsoft.com/office/174adf5f-846b-4780-b765-de1a0a737e2b ; https://support.microsoft.com/en-us/topic/a90c30f3-9940-4897-ab5b-988e69e4cd9c ; https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0
- [ ] First channel: no longer forced to be named "General"; can be renamed later; can't be archived or deleted. From May 2026 the first channel of a new team defaults to the **Threaded** layout (owners can switch to Posts).
  Source: https://support.microsoft.com/office/174adf5f-846b-4780-b765-de1a0a737e2b ; https://mc.merill.net/message/MC1283811 (via search summary)
- [ ] **More create team options** > **From template**: gallery of templates (Manage a Project, Manage an Event, Onboard Employees, Adopt Office 365, Organize Help Desk, Incident Response, Crisis Communications, Manage a Store, Bank Branch, Patient Care, Hospital, Quality and Safety, Retail for Managers, Manage Volunteers, Frontline Collaboration, plus org custom templates). Template detail page lists channels and apps > **Use this template** > choose Private/Public + sensitivity > name, description, rename provided channels > **Create**. Not in GCC. Template limits: 15 channels, 20 tabs/channel, 50 apps.
  Source: https://support.microsoft.com/en-us/topic/a90c30f3-9940-4897-ab5b-988e69e4cd9c ; https://learn.microsoft.com/en-us/microsoftteams/get-started-with-teams-templates-in-the-admin-console
- [ ] **From another team**: list of teams you're a member of; pick one, then name/description/privacy/sensitivity and checkboxes for what to copy: **channels**, **tabs**, **settings**, **apps**, **members**. Shared channels aren't copied. You still configure app/tab settings after.
  Source: https://support.microsoft.com/en-us/topic/24ec428e-40d7-4a1a-ab87-29be7d145865 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] **From a group**: lists Microsoft 365 groups you own that have no team and <10,000 members; selecting one creates a team with the same name, privacy, sensitivity and members. Not available for groups >10,000 or Viva Engage community groups.
  Source: https://support.microsoft.com/en-us/topic/24ec428e-40d7-4a1a-ab87-29be7d145865
- [ ] Creation restricted by org policy: show "can't create" state; per-user limit 250 owned teams (object limit); member of up to 1,000 teams; up to 100 owners and 25,000 members per team.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Org-wide team (global admin only, ≤10,000 users, max 5 per tenant): auto-adds everyone; members can't leave.
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Graph: `POST /teams` (from scratch/template, `template@odata.bind`, `firstChannelName`, `visibility`, async `teamsAsyncOperation`); `PUT /groups/{id}/team` (from group); `POST /teams/{id}/clone` (from another team, `partsToClone`: apps, tabs, settings, channels, members).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0

## 7. Join a team

- [ ] **New items** > **Join team** opens the join gallery: "Type to search" box (name or topic), grid of suggested/public team tiles; hover tile > **Join team**. Public = join immediately; private = **Ask to join** then wait for owner approval. Private teams only appear if the owner enabled discoverability.
  Source: https://support.microsoft.com/en-us/office/find-and-join-a-team-9f284981-39a1-486d-b43d-ab2dcc4c1e0f
- [ ] **Join a team with a code** card on the same page: **Enter join code** box + **Add team**. Code into a private team triggers an owner approval request. Guests can't join with link or code.
  Source: https://support.microsoft.com/en-us/office/use-a-link-or-code-to-join-a-team-c957af50-df15-46e3-b5c4-067547b64548
- [ ] Join via link (from **Get link to team**): opening the link joins a public team or shows a request-access screen for a private team.
  Source: https://support.microsoft.com/en-us/office/use-a-link-or-code-to-join-a-team-c957af50-df15-46e3-b5c4-067547b64548
- [ ] Graph: `POST /teams/{id}/members` (owner adds); join-requests and join codes have no documented Graph endpoint **[unverified]**.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0

## 8. Team ··· menu (More team options)

Items appear depending on role and team state. Owner view (desktop) includes:
- [ ] **Hide all channels** (removes team from list).
  Source: user guide PDF p.11
- [ ] **Manage team** (opens team management page; see §9).
  Source: https://support.microsoft.com/topic/ce053b04-1b8e-4796-baa8-90dc427b3acc
- [ ] **Add channel** (opens Create a channel with the team preselected).
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] **Add member** (owner: adds directly; member: submits a request owners approve).
  Source: https://support.microsoft.com/en-us/teams/teams-channels/add-members-to-a-team-in-microsoft-teams ; https://support.microsoft.com/en-us/office/find-and-join-a-team-9f284981-39a1-486d-b43d-ab2dcc4c1e0f
- [ ] **Leave** (desktop label; mobile **Leave team**) with a confirmation message; only an admin can remove you from an org-wide team. **[last-owner behaviour unverified]**
  Source: https://support.microsoft.com/en-us/office/leave-a-team-e481005d-3ec6-4694-b300-375472ba4076
- [ ] **Edit team** (name, description, privacy) **[label: verify]**; equivalent to Manage team > Settings > **Team details** > **Edit** > **Done**.
  Source: https://support.microsoft.com/topic/ce053b04-1b8e-4796-baa8-90dc427b3acc
- [ ] **Get link to team** (copies team URL; same as Graph `team.webUrl`).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0
- [ ] **Manage tags** (§16).
  Source: https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] **Archive team** (owner; from Your teams page or menu; checkbox **Make the SharePoint site read-only for team members**) / **Restore team** for archived teams.
  Source: https://support.microsoft.com/office/dc161cfd-b328-440f-974b-5da5bd98b5a7
- [ ] **Delete team** (trash icon; owner only; confirmation dialog **[confirmation checkbox text unverified]**). Deletes the team mailbox and calendar, SharePoint site and files, and the OneNote, Planner plan, Power BI workspace or Stream group tied to it. Owners and IT admins can recover it for 30 days.
  Source: https://support.microsoft.com/en-us/office/delete-a-team-in-microsoft-teams-c386f91b-f7e6-400b-aac7-8025f74f8b41
- [ ] Channel-in-team **Show in** > Favorites / custom section also available at team level for its channels. **[unverified for team row]**
- [ ] Graph: `PATCH /teams/{id}`; `DELETE /groups/{id}`; `POST /teams/{id}/archive` (`shouldSetSpoSiteReadOnlyForMembers`), `POST /teams/{id}/unarchive`; `DELETE /teams/{id}/members/{mid}` (leave/remove).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0

## 9. Manage team page

Opened via team … > **Manage team**. Tabs across the top: **Members**, **Pending requests**, **Channels**, **Settings**, **Analytics**, **Apps**, **Tags** (owners; members see a subset). **[exact tab set: verify on winpc]**

- [ ] **Members** tab: **Search members** box, **Add member** button, collapsible "Owners" and **Members and guests** groups; columns Name, Title, Location, Tags, Role (Owner/Member dropdown) **[column set unverified]**; **Remove** (X) on the far right of each row. To remove another owner, first change their role to Member. Owners can't remove people from the org.
  Source: https://support.microsoft.com/en-us/topic/91610d8b-c182-4cab-8f31-1ed8d3d316ee ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] Add member dialog: type name, distribution list, security group or Microsoft 365 group (DL/group import ≤3,500); external email addresses become guests; role dropdown next to each person (**Member** ▾ → **Owner**); **Add**.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/add-members-to-a-team-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] **Pending requests** tab: accept/deny join requests (from code, link, private-team "Ask to join", member-submitted adds).
  Source: https://support.microsoft.com/en-us/office/use-a-link-or-code-to-join-a-team-c957af50-df15-46e3-b5c4-067547b64548 ; https://support.microsoft.com/en-us/teams/teams-channels/add-members-to-a-team-in-microsoft-teams
- [ ] **Channels** tab: list of all channels (incl. private/shared the owner isn't in) with filter pills including active, and an overflow "4 more" filter containing **Archived** and **Deleted**; per channel **More options** > **Archive channel** / **Restore channel**; deleted channels have **Restore** (confirm screen **Restore**); per-channel "Show for me"/"Show for members" toggles **[unverified]**.
  Source: https://support.microsoft.com/en-us/topic/973f9014-53db-4165-8ab4-365021fe36b7 ; https://support.microsoft.com/en-us/teams/teams-channels/archive-or-restore-a-channel (via fetch summary)
- [ ] **Settings** tab, expandable groups:
  - **Team details**: **Edit** name, description, Public/Private > **Done**.
  - **Team picture**: change picture (owner only).
  - **Member permissions**: create and update channels; create private channels; create shared channels; delete and restore channels; add and remove apps; upload custom apps; create, update and remove tabs; create, update and remove connectors; owners can delete all messages; give members the option to edit/delete their sent messages; allow members to create tags **[labels paraphrased from Graph; verify exact strings]**.
  - **Guest permissions**: create and update channels; delete channels.
  - **@mentions**: who can use @team and @channel mentions; **Show members the option to @mention groups based on job title or department** (automatic tags).
  - **Team code**: **Generate** / copy / reset / remove a join code.
  - **Fun stuff**: enable Giphy (+ content rating), stickers and memes, custom memes.
  - **Tags**: who can manage tags; **Shifts** toggle for shift-based tags.
  Source: https://support.microsoft.com/topic/ce053b04-1b8e-4796-baa8-90dc427b3acc ; https://support.microsoft.com/topic/4756c468-2746-4bfd-a582-736d55fcc169 ; https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e ; https://support.microsoft.com/en-us/office/use-a-link-or-code-to-join-a-team-c957af50-df15-46e3-b5c4-067547b64548 ; https://support.microsoft.com/en-us/topic/d03fdf5b-1a6e-48e4-8e07-b13e1350ec7b ; https://learn.microsoft.com/en-us/graph/api/resources/teammembersettings?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/teammessagingsettings?view=graph-rest-1.0
- [ ] **Analytics** tab: date range; summary of users and meetings incl. active users; engagements (posts, replies, mentions, reactions); meetings held; **Select a channel** dropdown for channel-level analytics; link **Analytics across teams**.
  Source: https://support.microsoft.com/office/5b8ad4b1-af34-4217-aff4-cd11a820b56b
- [ ] **Apps** tab: list of installed apps with remove, and "More apps" / upload a custom app (if permitted). **[unverified]**
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0 (installedApps)
- [ ] **Tags** tab: create/edit/delete tags (same as Manage tags).
  Source: https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] Role capability matrix enforced in UI (owner vs member vs guest): guests can create channels (if allowed), take part in channel conversations, share channel files, edit/delete own posts; guests can't share chat files, add apps, create teams, discover/join public teams, view org chart. Owner-only: edit/delete team, set permissions for channels/tabs/connectors, change team picture, add guests, control @team / @channel mentions, allow emoji/GIFs/memes, renew, archive/restore. Members can add members directly only to public teams; private requires owner approval.
  Source: https://support.microsoft.com/en-us/topic/d03fdf5b-1a6e-48e4-8e07-b13e1350ec7b
- [ ] Team expiration/renewal: owner can **Renew** an expiring team (org expiration policy). **[UI location unverified]**
  Source: https://support.microsoft.com/en-us/topic/d03fdf5b-1a6e-48e4-8e07-b13e1350ec7b (capability "Renew a team")
- [ ] Graph: `GET/POST/PATCH/DELETE /teams/{id}/members` (+ `add`/`remove` bulk actions; `roles: ["owner"]`); `team.memberSettings` (allowCreateUpdateChannels, allowCreatePrivateChannels, allowDeleteChannels, allowAddRemoveApps, allowCreateUpdateRemoveTabs, allowCreateUpdateRemoveConnectors), `guestSettings` (allowCreateUpdateChannels, allowDeleteChannels), `messagingSettings` (allowUserEditMessages, allowUserDeleteMessages, allowOwnerDeleteMessages, allowTeamMentions, allowChannelMentions), `funSettings` (Giphy, stickers/memes, custom memes); `GET/PUT /teams/{id}/photo/$value`; `/teams/{id}/installedApps`; `team.summary` (owner/member/guest counts).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/teammembersettings?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/teammessagingsettings?view=graph-rest-1.0

## 10. Channel types

- [ ] **Standard**: open to all team members; posts searchable by all members; files in a folder of the team site; moderation supported; Planner, bots, connectors, message extensions supported; scheduled meetings supported; analytics supported.
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] **Private** (lock icon): subset of team members (guests allowed if team members); own SharePoint site; any owner/member can create by default (guests can't); private channel owner manages members (**Manage channel** > **Members**/**Settings** tabs); team owners not in the channel see it only under Manage team; team owners can delete/restore; settings inherited from team at creation then independent; no connectors, no Stream/Planner/Tasks/To Do/Forms tabs, no moderation, no Copy link to channel. Limits: legacy support docs say 30 private channels/team and 250 members; current Learn says private channels now count within the 1,000 channels/team and up to 5,000 members, and now support channel meetings. Last owner can't leave/be removed; a member is auto-promoted if the owner leaves the org. Users removed from team are removed from all private channels.
  Source: https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] **Shared** (shared icon): only team owners create; members can be added without adding them to the team, including people in other orgs via B2B direct connect (Entra guests can't be added); can be shared with up to 50 other teams (each counts as one member), 5,000 direct members; own SharePoint site; inherits sensitivity label and description from host team; no bots/connectors/message extensions; tabs supported except Stream, Planner, Forms; scheduled meetings supported; tags supported; no moderation, no analytics, no class teams; can't change host team or type; team owners see shared channel names but not content unless members. Appears in other teams' lists as an incoming channel.
  Source: https://learn.microsoft.com/en-us/microsoftteams/shared-channels ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview
- [ ] No conversion between channel types; private/shared can't move teams.
  Source: https://support.microsoft.com/office/de3e20b0-7494-439c-b7e5-75899ebe6a0e
- [ ] Graph: `channel.membershipType` = `standard` | `private` | `shared`; `POST/GET/PATCH/DELETE /teams/{id}/channels/{cid}/members` (private/shared only); `GET /channels/{cid}/allMembers`; `GET /channels/{cid}/sharedWithTeams` (+ delete to unshare; `allowedMembers`); `GET /channels/{cid}/doesUserHaveAccess`; `DELETE /teams/{id}/incomingChannels/{cid}`; `channel.summary` (owner/member/guest counts, hasMembersFromOtherTenants).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 11. Create a channel

- [ ] Entry points: **New items** > **New channel** (then pick team in "Add the channel to a team *" picker showing team avatar, privacy and member count); team … > **Add channel**; Your teams page > team … > **Add channel**.
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 ; Threads PDF p.2
- [ ] "Create a channel" dialog fields: **Add the channel to a team** * (info i); **Channel name** * (placeholder "Letters, numbers, and spaces are allowed"); **Description**; **Choose a channel type** * (info i) dropdown: "Standard — Everyone on the team has access", "Private — Specific teammates have access", "Shared — People you choose from your org or other orgs have access" **[private/shared option text: verify]**; **Layout** ("Channel owners can change this at any time") with two picture cards: **Threads** (badge "New"; "Looks like chat with replies on the side in threads. Good for back-and-forth discussions") and **Posts** ("Posts reorder by most recent reply. Good for forums and announcements"); **Cancel** / **Create**.
  Source: Threads PDF p.2 (screenshot) ; https://support.microsoft.com/en-us/topic/9ee3c43f-8bbc-4fe2-89f3-88d618e8296c
- [ ] Channel name validation: max 50 chars; disallowed characters `~ # % & * { } + / \ : < > ? | ' " ,` and `..`, control ranges 0x00-0x1F and 0x80-0x9F; reserved words forms, CON, CONIN$, CONOUT$, PRN, AUX, NUL, COM1-COM9, LPT1-LPT9, desktop.ini, _vti_; can't start with `_` or `.` or end with `.`. A deleted channel's name can't be reused during its restore window.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0 ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] After creating a private channel: add-members step (search team members, set role). After choosing Shared: people picker (org names, external emails), default **Share this channel with everyone on the team** option, role dropdown **Member** ▾ → **Owner**, **Share** then **Done**.
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] Limits: 1,000 channels per team over its lifetime incl. deleted (any mix of types).
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Graph: `POST /teams/{id}/channels` (`displayName`, `description`, `membershipType`, `layoutType`, `members` for private/shared).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 12. Channel ··· menu (More channel options in the list)

- [ ] **Manage notifications** / **Channel notifications** (opens "Channel notification settings" dialog; §19).
  Source: https://support.microsoft.com/en-us/topic/c72b8c07-37e1-4a0b-82c9-fdfda04f15b2 ; Threads PDF p.13
- [ ] **Show in** › **Favorites** / custom sections / **New section** (or **Move to** for items already in a section). Older builds: **Pin** / **Unpin**.
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8 ; user guide PDF p.5
- [ ] **Hide** (and **Show** from See all channels).
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8
- [ ] **Mark as read** / **Mark as unread**. **[unverified label for channel rows]**
- [ ] **Manage channel** (§13).
  Source: https://support.microsoft.com/en-us/topic/6ac54758-3440-4f6a-9bd5-cebf97cb7ea6
- [ ] **Edit channel** dialog: **Channel name** (must be unique in team; rejects `/ \ : * ? " < > |`; only team owners can rename the first channel, and only owners may name it "General"), **Description** (General/first channel shares the team description), checkbox **Recommend that people show this channel in their channel lists** (standard channels; up to 10 recommended per team; recommended channels get a "recommended" tag for new members; first/General channel is always recommended), **Layout**: **Threads** / **Posts**; **Save**. Hidden ("Edit this channel" missing) if owner restricted member permissions. Rename propagates to list, search, SharePoint, notifications.
  Source: https://support.microsoft.com/en-US/teams/teams-channels/edit-a-channel-in-microsoft-teams ; https://support.microsoft.com/en-us/topic/9ee3c43f-8bbc-4fe2-89f3-88d618e8296c
- [ ] Channels named "General" sort to the top of their team in the Teams and channels list.
  Source: https://support.microsoft.com/en-US/teams/teams-channels/edit-a-channel-in-microsoft-teams
- [ ] **Add members** (private/shared channels) ; **Share channel** › **With people** / **With a team you own** / **With a team** (shared channels, owners).
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 ; https://support.microsoft.com/en-US/teams/teams-channels/share-a-channel-with-people-in-microsoft-teams (via search summary)
- [ ] **Get email address** (hidden when admin disabled channel email; not in GCC/GCCH/DoD).
  Source: https://support.microsoft.com/topic/ce053b04-1b8e-4796-baa8-90dc427b3acc ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] **Get link to channel** / **Copy link** (standard channels only; private and shared channels don't support Copy link to channel).
  Source: https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview ; https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0
- [ ] **Open in new window** (pop out channel). **[unverified for channel row; thread/message menus do have "Open in new window"]**
  Source: Threads PDF p.9 (message and thread … menus)
- [ ] **Archive channel** / **Restore channel**.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/archive-or-restore-a-channel (via fetch summary)
- [ ] **Leave channel** (private/shared; not last owner).
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 ; https://learn.microsoft.com/en-us/microsoftteams/private-channels
- [ ] **Delete this channel** (confirmation; owners decide whether members can delete).
  Source: https://support.microsoft.com/en-us/topic/973f9014-53db-4165-8ab4-365021fe36b7
- [ ] Channel-header **More channel options** (… at top right of an open posts channel) adds **See new posts at top** / **See new posts at bottom** (flip post order).
  Source: https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992
- [ ] Graph: `PATCH /teams/{id}/channels/{cid}`; `DELETE` channel; `POST .../archive` / `.../unarchive`; `POST .../provisionEmail` / `.../removeEmail`; `channel.email`, `channel.webUrl`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 13. Manage channel page

- [ ] Opened via channel … > **Manage channel**. Top tabs: **Members** (private/shared), **Settings**, **Analytics** (standard/private), **Requests and invites** (shared). Settings tab sections include **Channel details** (**Edit** under "Edit channel name and description"), moderation, and connectors.
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 ; https://support.microsoft.com/office/5b8ad4b1-af34-4217-aff4-cd11a820b56b
- [ ] **Settings** > **Who can start a new post?**: **Everyone can start a new post** / **Everyone except guests can start a new post** (basic moderation without turning moderation on).
  Source: https://support.microsoft.com/en-us/topic/6ac54758-3440-4f6a-9bd5-cebf97cb7ea6
- [ ] **Channel moderation**: **On**/**Off** (standard channels only; not General/first channel, not private). When On, only moderators can start new posts. **Who are the moderators?** > **Manage** (add/remove team members; owners are moderators by default and can't be removed). **Team member permissions** checkboxes: allow members to reply to channel messages; allow members to pin channel messages; allow bots to submit channel messages; allow connectors to submit channel messages.
  Source: https://support.microsoft.com/en-us/topic/6ac54758-3440-4f6a-9bd5-cebf97cb7ea6
- [ ] **Analytics**: date range; users, meetings, posts, replies, mentions, reactions for the channel.
  Source: https://support.microsoft.com/office/5b8ad4b1-af34-4217-aff4-cd11a820b56b
- [ ] Private/shared **Members** tab: add/remove, role Owner/Member, last owner protection; **Settings** tab: what members may do (tabs, @channel mention) independent of team.
  Source: https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/shared-channels
- [ ] Threads layout conversion is also reachable from **Manage channel** (adoption guide) as well as **Edit channel**.
  Source: Threads PDF p.1
- [ ] Graph: channel moderation settings exist only in beta (`channel.moderationSettings`: `userNewMessageRestriction` everyone/everyoneExceptGuests/moderators, `replyRestriction`, `allowNewMessageFromBots`, `allowNewMessageFromConnectors`).
  Source: https://learn.microsoft.com/en-au/graph/api/resources/channelmoderationsettings?view=graph-rest-beta (via search summary)

## 14. Channel layouts: Posts vs Threads

- [ ] Two layouts per channel, chosen at creation ("Layout") or switched later by channel owners / permitted members: channel … > **Edit channel** > **Conversation layout** > **Threads layout** / **Posts layout** > **Save**. Switching is reversible and keeps content.
  Source: https://support.microsoft.com/en-us/topic/9ee3c43f-8bbc-4fe2-89f3-88d618e8296c ; https://adoption.microsoft.com/files/microsoft-teams/Threads-layout-in-Microsoft-Teams-channels_FAQ.pdf
- [ ] Posts layout: first tab named **Posts**; conversations are cards with optional subject, replies nested under the post, and the whole conversation re-orders by recency of replies; "Post in channel" / "Start a post" composer; better for announcements and moderation.
  Source: https://adoption.microsoft.com/files/microsoft-teams/Threads-layout-in-Microsoft-Teams-channels_FAQ.pdf ; https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992
- [ ] Threads layout: first tab named **Conversation**; chat-like flat main canvas (chronological, newest at bottom) with a "Type a message" composer at the bottom (no "Start a post" step); empty state "Welcome to the <name> channel — This channel is set to a threads layout. Reply to a message to start a thread away from the main conversation."
  Source: https://adoption.microsoft.com/files/microsoft-teams/Threads-layout-in-Microsoft-Teams-channels.pdf (p.3) ; https://practical365.com/teams-threaded-layout/
- [ ] Under each root message with replies: stacked avatars of repliers + "**N replies**" link + "Last reply <time>"; hover adds **Follow** affordance. Clicking "N replies" opens the thread in the right side pane.
  Source: Threads PDF p.4-8
- [ ] **Reply in thread** hover action on any message opens a "New Thread" right pane with the root message and a composer. Thread pane header: ← back, root-message title (truncated), Copilot/summary icon, …, ✕. Composer has "**Send to: thread only ▾**" selector with **Thread only** / **Thread and channel**; "Thread and channel" also posts into the main canvas marked "Also sent to channel" (and in canvas "Replied in thread <time>" link). Placeholder "Reply in thread".
  Source: Threads PDF p.3-6 ; https://practical365.com/teams-threaded-layout/ ("Reply in thread only" / "Reply in thread and channel")
- [ ] Threads list pane: header button **Open threads** (to the right of Meet now) opens a "Threads" side pane listing all threads in the channel, bold for unread, ordered by most recent reply, each showing root author/avatar, title (subject in bold), latest reply preview, reply count and participant avatars.
  Source: Threads PDF p.7 ; https://practical365.com/teams-threaded-layout/
- [ ] Follow thread: auto-follow if you authored the root, replied, or were @mentioned (configurable in Settings); manual via message hover … > **Follow thread**, via hover on replies row **Follow**, or thread pane header … > **Follow thread**. Unfollow from the same places.
  Source: Threads PDF p.8-9
- [ ] Message … menu in threads layout (screenshot order): **Forward**, **Follow thread**, **Copy link**, **Pin**, **Open in new window**, separator, **Mark as unread**, **Immersive Reader**, **Translate** ›, separator, **Report this message**, separator, **More actions** ›.
  Source: Threads PDF p.9 (screenshot)
- [ ] Thread pane header … menu: **Follow thread**, **Mark as unread**, **Copy link**, **Jump to original message**, **Open in new window**.
  Source: Threads PDF p.9 (screenshot)
- [ ] Subjects in threads layout: new messages can't set a subject at compose time; you post, then **Edit** to add a subject; subjects show bold in the threads pane.
  Source: https://practical365.com/teams-threaded-layout/
- [ ] Mixed-client compatibility banner on Posts-rendered threaded channels: "Some channel participants have reply threads, a new way to reply. **Learn more**" with ✕. Clients without threads see posts with replies; posts can appear out of order; bold/notifications may misbehave. EDU tenants always see posts layout; some guests/external users see posts layout.
  Source: Threads PDF p.14 ; https://support.microsoft.com/en-us/topic/9ee3c43f-8bbc-4fe2-89f3-88d618e8296c
- [ ] Admin control: Teams channel policy "ThreadedChannelCreation" (PowerShell ≥7.1 / admin center) blocks creating/converting to threads; existing threaded channels keep working.
  Source: https://practical365.com/teams-threaded-layout/ ; https://mc.merill.net/message/MC1088172
- [ ] Graph: `channel.layoutType` = `post` | `chat` (settable on create and PATCH); thread replies via `POST /teams/{id}/channels/{cid}/messages/{mid}/replies`; `chatMessage.replyToId`, `chatMessage.subject`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0

## 15. Posting in channels (posts layout), announcements, cross-posting

- [ ] Post order toggle: channel header **More channel options** > **See new posts at top** / **See new posts at bottom**. With new posts at top, a **Post in channel** button sits at the top; at bottom, it's at the bottom. Settings also has **When I go to a channel, show recent activity: At the top / At the bottom**.
  Source: https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992 ; Threads PDF p.12
- [ ] **Post in channel** / **Start a post** expands the full post composer: **Add a subject** line, rich body with formatting toolbar, **Post type** selector next to **Post** (values **Post** / **Announcement**), **Actions and apps** (+) menu, attach, emoji/GIF/sticker, **Post** button. **[compose toolbar items: verify]**
  Source: https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992 ; https://support.microsoft.com/en-us/topic/9c1252a3-67ef-498e-a7c1-dd7147b3d295
- [ ] Announcement: toolbar **Announcement** (megaphone) when posting at top; **Post type** > **Announcement** when posting at bottom; in threads layout: "Type a message" > **Actions and apps** > **Announcement**. Announcement composer: large **headline** banner, optional **subhead**, **Color scheme** (preset backgrounds) or **Upload an image** background; newer clients offer **Create with Designer** AI background. Announcements only in channels, not chats.
  Source: https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992 ; https://mc.merill.net/message/MC687791 (via search summary)
- [ ] Cross-post: in composer **Actions and apps** > **Post in other channels**; a "+" above the subject adds channels; picker lists channels you're a member of with search; **Update** saves; target channel chips with X to remove; **Post** sends to all. Editing a cross-post (… > **Edit**) can add/remove channels; any existing post can be turned into a cross-post. Only channels where you can post (moderation respected). Replies stay per channel. **[limit: 50 channels per third-party source]**
  Source: https://support.microsoft.com/en-us/topic/9c1252a3-67ef-498e-a7c1-dd7147b3d295 ; https://office365itpros.com/2019/10/25/post-to-multiple-teams-channels/amp/ (via search summary)
- [ ] Reply in posts layout: **Reply** link under each conversation opens an inline reply composer; replies collapse as "N replies from A, B and C" with expand.  **[verify strings]**
  Source: https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 (general) ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0 (replies)
- [ ] Post size limit ~100 KB per post (incl. mentions, reactions; excl. base64 images); team/channel mentions blocked in teams >10,000 members.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Mark importance (normal/high/urgent) on posts and messages. **[UI location unverified]**
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0 (`importance`)
- [ ] Pin a channel message (subject to moderation permission "pin channel messages"); pinned items show at the top/channel info. **[pinned-post surface unverified]**
  Source: https://support.microsoft.com/en-us/topic/6ac54758-3440-4f6a-9bd5-cebf97cb7ea6 ; Threads PDF p.9 (Pin in message menu)
- [ ] Graph: `POST /teams/{id}/channels/{cid}/messages` (subject, body, importance, mentions, attachments incl. announcement card is not documented **[unverified]**); `GET .../messages`, `.../messages/{mid}/replies`, `softDelete`/`undoSoftDelete`, `setReaction`/`unsetReaction`; `GET /teams/{id}/channels/getAllMessages`; change notifications on channel messages.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0

## 16. Shared channel sharing flows

- [ ] Channel … > **Share channel** › **Share with people**: people picker (org names; external email addresses for B2B direct connect), **Share**; role dropdown **Member** ▾ → **Owner**; **Close**. External people can only be members. Recipients are notified and get access immediately. Mobile: tap channel name > **Manage members** > **Add members** > **Done**.
  Source: https://support.microsoft.com/en-US/teams/teams-channels/share-a-channel-with-people-in-microsoft-teams
- [ ] Channel can also be shared "from its channel card" (channel info card opened from the channel name). **[card layout unverified]**
  Source: https://support.microsoft.com/en-US/teams/teams-channels/share-a-channel-with-people-in-microsoft-teams
- [ ] **Share channel** › **Share with a team you own**: type team name > **Done**; team members get immediate access.
  Source: https://support.microsoft.com/en-us/office/share-a-channel-with-a-team-b2e89992-2708-4583-b11e-bbb6edb4f1c3
- [ ] **Share channel** › **Share with a team**: type the other team's owner (name in org, email outside org) > **Send invite**. Sent invites listed in **Manage channel** > **Requests and invites**. Invitee owner sees an Activity item: **Accept** / **Decline**, then picks which of their teams > **Done** (14 days). Channel owner then gets an Activity item to **Approve** / **Deny** the team (14 days), seeing team name, member count, public/private, org.
  Source: https://support.microsoft.com/en-us/office/share-a-channel-with-a-team-b2e89992-2708-4583-b11e-bbb6edb4f1c3
- [ ] Shared channels appear inside every team they're shared with (incoming channel) and show the host team context; team owners can remove an incoming channel from their team.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0 (incomingChannels, Remove incoming channel)
- [ ] Archiving a host team keeps individual sharing but removes sharing with other teams; deleting/restoring team or channel restores sharing relationships (30 days).
  Source: https://learn.microsoft.com/en-us/microsoftteams/shared-channels
- [ ] Shared-channel role model: team owners create shared channels, accept invites sent to their team, see name/description of all shared channels, delete/restore them, remove a team from a shared channel, but can't see files/conversations/members unless added; channel owners add/remove owners and members, edit/delete, restore, override inherited settings; removing someone from the team doesn't remove a directly shared member; ownerless channel auto-promotes a member.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/shared-channel-owner-and-member-roles-in-microsoft-teams
- [ ] Graph: `POST /teams/{id}/channels/{cid}/members` (incl. external `tenantId`); `GET/DELETE .../sharedWithTeams/{tid}`; `GET .../sharedWithTeams/{tid}/allowedMembers`; `GET .../doesUserHaveAccess(userId=…,tenantId=…)`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 17. Tags

- [ ] Manage tags: team … > **Manage tags** (or Manage team > **Tags**): create tag (name, description, assign team members), edit, delete. Custom tags by owners (or members if allowed); **Shift-based** tags from Shifts (toggle **Shifts** under Settings > **Tags**); **Automatic** tags by job title/department set up by IT admin (owner enables via **@mention** section checkbox **Show members the option to @mention groups based on job title or department**).
  Source: https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] Use: type @ + tag name in a channel post, select from the suggestion list; tag renders like a mention; all tag members are notified (Activity + **Tag mentions** quick view). Start a chat with a tag: **New message**, type tag name in To:, all members added.
  Source: https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] Shared channels: only direct members of the shared channel can be in its tags. Not available in Air Gap.
  Source: https://support.microsoft.com/en-us/topic/667bd56f-32b8-4118-9a0b-56807c96d91e
- [ ] Limits: 200 tags/team, 25 suggested default tags/team, 200 members per tag, 25 tags per user per team.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Members tab shows each member's tags column. **[unverified]**
- [ ] Graph: `GET/POST /teams/{id}/tags`, `GET/PATCH/DELETE /teams/{id}/tags/{tagId}`, `/tags/{tagId}/members`; `tagType` = `standard` | `scheduled`; mention entity type `tag` in chatMessage.mentions.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/teamworktag?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessage?view=graph-rest-1.0

## 18. @team / @channel mentions

- [ ] Mention suggestion list in channel compose (type @ then name, pick from menu) offers people, tags, **@<team name>** (notifies everyone on the team) and **@<channel name>** (notifies everyone in that channel); `@team`/`@channel` aliases also resolve **[aliases per third-party guides]**; chats use **@everyone** instead. Team/channel mentions work only once a team owner enables them. Selecting a mention notification jumps to the exact point in the conversation. Cross-team channel mentions not allowed **[third-party]**.
  Source: https://support.microsoft.com/en-us/office/use-mentions-to-get-someone-s-attention-in-microsoft-teams-eb4f059d-320e-454e-b111-03361d4d6855 ; https://learn.microsoft.com/en-us/graph/api/resources/chatmessagementionedidentityset?view=graph-rest-1.0
- [ ] Owners control availability: Manage team > Settings > **@mentions** (who can use @team, @channel); private/shared channels have their own @channel setting in Manage channel > Settings. Team/channel mentions blocked automatically for teams >10,000 members.
  Source: https://support.microsoft.com/en-us/topic/d03fdf5b-1a6e-48e4-8e07-b13e1350ec7b ; https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Channel mention notifies members who show the channel (and per-channel "Channel mentions" setting); team mention notifies all team members (per-channel "Team mentions" preset option). **[delivery semantics: verify]**
  Source: https://mc.merill.net/message/MC1388719
- [ ] Graph: `chatMessageMention.mentioned.conversation` with `conversationIdentityType` `team` | `channel`; `team.messagingSettings.allowTeamMentions` / `allowChannelMentions`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/chatmessagementionedidentityset?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/teammessagingsettings?view=graph-rest-1.0

## 19. Channel and team notifications

- [ ] Per-channel entry: channel **More channel options** > **Manage notifications** (current support label; older/adoption builds **Channel notifications**). Options: turn notifications for all new messages (threads) or posts (posts layout) on/off, delivery **Activity feed and banner** vs **only the Activity feed**; threads layout adds **Include thread replies** and **Follow all new threads** (feeds the Followed threads quick view; doesn't notify in Activity).
  Source: https://support.microsoft.com/en-us/topic/c72b8c07-37e1-4a0b-82c9-fdfda04f15b2
- [ ] Dialog layout: channel … > **Channel notifications** opens "**Channel notification settings**" (subtitle "<Team> > <Channel>"): **Notify me for all new messages** dropdown (e.g. **Show in Activity and banner**, **Only show in Activity**, **Off**) with checkbox **Include thread replies** (posts layout: **All new posts** + **Include all replies**); **Channel mentions** dropdown; **Follow all new threads** toggle ("Threads you participate in or are @mentioned in are auto-followed. Choose where you get notified in settings. **Go to Settings**"); **Cancel** / **Save**. **[dropdown option strings: verify]**
  Source: Threads PDF p.13 (screenshot) ; https://support.microsoft.com/en-us/topic/c72b8c07-37e1-4a0b-82c9-fdfda04f15b2 (via search summary)
- [ ] 2026 granular presets (rolling out Oct-Nov 2026): **All new messages**, **Mentions and replies**, **Mute**, each customizable per channel for unfollowed threads, tag mentions, channel mentions, team mentions, and banner notifications for the channel.
  Source: https://mc.merill.net/message/MC1388719
- [ ] Global: **Settings and more** > **Settings** > **Notifications and activity**: replies to followed threads and posts On/Off, shown in Activity feed and banner or Activity feed only (applies to all Posts and Threads channels). Chats and channels section also governs followed threads/posts replies, channel mentions, team mentions, tag mentions, "new messages in threads layout channels" (Activity feed), with delivery **Banner and feed** / **Only show in feed** / **Off**. **[exact strings: verify]**
  Source: https://support.microsoft.com/en-us/topic/c72b8c07-37e1-4a0b-82c9-fdfda04f15b2 ; Threads PDF p.12 ; https://adoption.microsoft.com/files/microsoft-teams/Threads-layout-in-Microsoft-Teams-channels_FAQ.pdf
- [ ] Hidden channels still deliver @mention, @tag and followed-thread notifications.
  Source: https://support.microsoft.com/en-us/topic/91a37043-acea-49b0-9dfc-aec37b2e92b8
- [ ] Shared and private channel notifications are excluded from missed-activity emails.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://learn.microsoft.com/en-us/microsoftteams/private-channels
- [ ] Graph: no endpoint for per-user channel notification preferences. **[unverified]**

## 20. Channel tabs

- [ ] Default tabs: first tab **Posts** (posts layout) or **Conversation** (threads layout); **Shared** (formerly **Files**). Posts/Conversation and Shared can't be removed. Legacy channels may still show **Wiki** (or **Notes** for OneNote).
  Source: https://support.microsoft.com/en-us/office/83d0514f-2134-4db5-80f2-e9b43e111d57 ; Threads PDF p.3-4 (tab strip "Conversation  Shared  Wiki  +")
- [ ] **Add a tab** (+ at end of tab strip): app picker (search, app tiles); pick app > configure > **Add**/**Save**. File tab: pick Word/Excel/PowerPoint/PDF app then choose from files already shared in the channel > **Save**. Checkbox **Post to the channel about this tab** (default checked) creates a post announcing the tab.
  Source: https://support.microsoft.com/en-us/office/83d0514f-2134-4db5-80f2-e9b43e111d57
- [ ] Alternate entry: header **Open apps** > search > pick app > **Add a tab** > tab name > **Save** (e.g. Channel calendar).
  Source: https://support.microsoft.com/en-us/office/add-a-shared-channel-calendar-472657b8-f270-4a4a-a14c-b8daace0bb56
- [ ] Tab context (right-click or tab ▾): **Copy link to tab**, **Rename**, **Remove**, **Settings**, **Pop out tab**, **Move** (left/right) **[only Copy link to tab, Rename (Lists), Remove are confirmed in docs]**; drag tabs to reorder **[unverified]**.
  Source: https://support.microsoft.com/en-us/office/83d0514f-2134-4db5-80f2-e9b43e111d57 ; https://support.microsoft.com/en-US/Teams/teams-channels/rename-or-remove-a-list-in-a-teams-channel (via search summary)
- [ ] **Show tab conversation** button inside a tab toggles a side discussion; replies also appear as replies to the original tab post in the channel.
  Source: https://support.microsoft.com/en-us/office/83d0514f-2134-4db5-80f2-e9b43e111d57
- [ ] Permissions: removing tabs allowed per team owner setting (member permission "create, update, and remove tabs"); private/shared channel tabs controlled by channel owner.
  Source: https://support.microsoft.com/en-us/office/83d0514f-2134-4db5-80f2-e9b43e111d57 ; https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/graph/api/resources/teammembersettings?view=graph-rest-1.0
- [ ] Built-in tab types to support/render: Website (`com.microsoft.teamspace.tab.web`), Word/Excel/PowerPoint/PDF static viewers, Document library (`com.microsoft.teamspace.tab.files.sharepoint`), Wiki (`com.microsoft.teamspace.tab.wiki`, legacy; "Set up tab"), Planner, Stream, Forms, OneNote (`0d820ecd-def2-4297-adad-78056cde7c78`), Power BI, SharePoint page/list (`2a527703-1f6f-4559-a332-d8a7d288cd88`), Channel calendar, Lists, Loop/"Page" **[Page/Loop tab not covered by fetched docs]**.
  Source: https://learn.microsoft.com/en-us/graph/teams-configuring-builtin-tabs ; https://learn.microsoft.com/en-us/microsoftteams/get-started-with-teams-templates-in-the-admin-console
- [ ] Private channels: no Stream, Planner, Tasks by Planner and To Do, Forms tabs; shared channels: no Stream, Planner, Forms.
  Source: https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Graph: `GET/POST/PATCH/DELETE /teams/{id}/channels/{cid}/tabs` (`teamsApp@odata.bind`, `configuration` entityId/contentUrl/websiteUrl/removeUrl, `displayName`, `webUrl`); `GET /channels/{cid}/enabledApps`.
  Source: https://learn.microsoft.com/en-us/graph/teams-configuring-builtin-tabs ; https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 21. Shared (Files) tab

- [ ] Channel **Shared** tab (renamed from **Files**) with two views: **In library** (the channel's SharePoint folder; old Files behavior) and **In posts** (files and links shared in channel messages). **[third-party source; verify view names on winpc]**
  Source: https://itsupport.mccneb.edu/TDClient/60/Portal/KB/ArticleDet?ID=3867 (via search summary) ; https://chrismenardtraining.com/post/how-to-search-files-in-microsoft-teams-channels-new-shared-tab-tutorial/ (via search summary)
- [ ] Files/Shared tab actions confirmed in docs: **Show actions** (…) > **Open in SharePoint**; More options > **Sync**.
  Source: https://support.microsoft.com/en-us/topic/ad00c29d-6b65-4fa0-83bf-ddd0f1b91427
- [ ] Shared tab confirmed actions: each channel has its own folder; **Shared** at the top of the channel opens it; **Upload** (file picker > **Open**) and drag-and-drop files into the list; **Shared** > **More commands** > **Sync** and > **Open in SharePoint**; two-way sync with the SharePoint site; recovering a renamed/deleted channel folder via SharePoint details pane > Activity. Uploaded files are visible to all channel members. Share dialog: people/group/email, optional message, **Link settings** (e.g. **People you choose** > **Apply**), permission dropdown **Can edit** / **Can review** / **Can view**, **Copy link**, **Send**.
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Library toolbar: **New** (folder, Word, Excel, PowerPoint, OneNote, Forms for Excel, link…), **Upload** (files/folder), **Edit in grid view**, **Share**, **Copy link**, **Sync**, **Add shortcut to OneDrive**, **Download**, **More commands** (…) > **Open in SharePoint**; per-file … menu: Open (in Teams / desktop app / browser), Share, Copy link, Make this a tab, Download, Delete, Pin to top, Rename, Open in SharePoint, Move to, Copy to, Version history, Details. **[items beyond Upload/Sync/Open in SharePoint/Share/Copy link unverified]**
  Source: https://support.microsoft.com/en-us/teams/files/collaborate-on-files-in-microsoft-teams
- [ ] Storage: standard channels = folder in team site document library; private/shared channels = their own SharePoint site (template TEAMCHANNEL#0/#1); files shared in posts auto-saved to the library; per-file limit 250 GB.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams ; https://learn.microsoft.com/en-us/microsoftteams/private-channels
- [ ] Graph: `GET /teams/{id}/channels/{cid}/filesFolder` (driveItem) then standard drive APIs (`/drives/{driveId}/items/{id}/children`, upload, createLink, etc.).
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 22. Channel meetings and Meet now

- [ ] Header **Meet now** button with ▾: click = instant channel meeting (**Join now** prejoin; doesn't ring anyone; anyone can drop in; shows as a live meeting post/thread in the channel). ▾ > **Schedule a meeting** (or **Schedule meeting**) opens the scheduler with the channel prefilled; **Add required attendees** / **Send personal invites** toggle to put it on people's calendars; **Send**.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/channel-meetings-in-microsoft-teams ; Threads PDF p.11-12
- [ ] Each channel meeting gets its own conversation thread in the channel; in threads layout the meeting card shows date tile, title, time, location, "<Team> > <Channel>", **Meeting details**, **Start a thread**, …. Meeting chat messages appear in that thread.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/channel-meetings-in-microsoft-teams ; Threads PDF p.11
- [ ] Scheduling not supported in private channels per support article; Learn (2026) says private channels now support channel meetings. Shared channels support scheduled meetings.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/channel-meetings-in-microsoft-teams ; https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/teams-channels-overview
- [ ] Graph: channel meeting = `onlineMeeting`/calendar event with `channelIdentity`; no simple "meet now in channel" Graph call. **[unverified]**

## 23. Channel calendar

- [ ] Channel calendar app as a tab: **Open apps** (or + Add a tab) > search "Channel" > **Channel calendar** > **Add a tab** > tab name > **Save**. Filtered view of the team's group calendar showing only that channel's events; accessible to the whole team; week view with **+ Add new event** and **Meet now** **[UI details unverified]**. Not available in private channels; guests can't view; events only in Teams.
  Source: https://support.microsoft.com/en-us/office/add-a-shared-channel-calendar-472657b8-f270-4a4a-a14c-b8daace0bb56 (+ search summary)
- [ ] Alternative: Outlook group calendar via Website tab.
  Source: https://support.microsoft.com/en-us/office/add-an-outlook-group-calendar-1a885b0d-32d1-4a78-81ea-1c2bb3ad4364 (via search summary)

## 24. Channel email

- [ ] Channel … > **Get email address** dialog: shows address with **Copy**; **advanced settings** link: who can send — **Anyone can send emails to this address** / **Only members of this team** / **Only email sent from these domains** (domain list); **Remove email address**. Hidden if admin disabled. **[radio labels paraphrased; verify]**
  Source: https://support.microsoft.com/topic/ce053b04-1b8e-4796-baa8-90dc427b3acc
- [ ] Inbound email renders as a channel post; replying in Teams is a normal channel reply (no email goes back to the sender; discussion invisible outside Teams). **View original email** link under the post opens the original (needed for oversized mail; attachments saved to the channel folder get a unique ID suffix on their file names). Failures: feature disabled, moderation/sender restrictions, >50 inline images, >20 attachments, attachment >10 MB, channel address used via a distribution list, channel SharePoint folder renamed/deleted/unsynced, anti-spam block; spoofing unsupported. Mobile can read/reply/view original but can't get the address.
  Source: https://support.microsoft.com/en-us/topic/ad00c29d-6b65-4fa0-83bf-ddd0f1b91427
- [ ] Inbound email limits: Limits: message 24 KB body (larger becomes a preview + download link), 20 attachments <10 MB each, 50 inline images; throttle 6 emails/10 s/channel/user. Not in GCC/GCCH/DoD.
  Source: https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Graph: `channel.email`; `POST /teams/{id}/channels/{cid}/provisionEmail`; `POST .../removeEmail`.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 25. Archive, delete, restore, leave

- [ ] Archive team: owner, from Your teams page (**All**) > team **More options** > **Archive team**; optional **Make the SharePoint site read-only for team members**. Archived teams appear under dropdown **Archived Teams**; read-only but searchable; no new posts/replies/channel changes/settings/apps; owners can still manage members/roles, delete, renew, restore (**More options** > **Restore team**). Add to Favorites to see on mobile.
  Source: https://support.microsoft.com/office/dc161cfd-b328-440f-974b-5da5bd98b5a7
- [ ] Archive channel: team owners (standard/private/shared) and channel owners (private/shared): Your teams and channels > **All** > channel **More options** > **Archive channel**, or bulk from Manage team > **Channels**; optional read-only SharePoint/Wiki checkbox. Archived icon next to name; Manage team > Channels > "4 more" > **Archived** filter; **Restore channel** from channel … menu. Team archive/restore doesn't change channel archive state. First channel can't be archived.
  Source: https://support.microsoft.com/en-us/teams/teams-channels/archive-or-restore-a-channel ; https://support.microsoft.com/office/174adf5f-846b-4780-b765-de1a0a737e2b
- [ ] Delete channel: channel … > **Delete this channel** (confirm) — deletes conversation history; OneNote sections stay in SharePoint. Restore: Manage team > **Channels** > "4 more" > **Deleted** > **Restore** > confirm **Restore**. Window stated as 21 days (Delete article) vs 30 days (Create-channel article, Learn limits); name can't be reused in the window; deleted channels count toward the 1,000 limit during it.
  Source: https://support.microsoft.com/en-us/topic/973f9014-53db-4165-8ab4-365021fe36b7 ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525 ; https://learn.microsoft.com/en-us/microsoftteams/limits-specifications-teams
- [ ] Delete team: owner only; team … > **Delete team** > confirm; removes mailbox/calendar, SharePoint site, OneNote, Planner, Power BI workspace, Stream group; owners/admins can recover within 30 days (restores shared channels and their sharing). Your teams page > **Teams you own** lists teams you can delete. Note: the "Recover a deleted team or channel" article says team recovery needs the IT admin (no in-client restore for teams); channel restore brings back conversations, files and tabs.
  Source: https://support.microsoft.com/en-us/office/delete-a-team-in-microsoft-teams-c386f91b-f7e6-400b-aac7-8025f74f8b41 ; https://support.microsoft.com/en-us/topic/dceed715-7732-46f1-966c-d1c348642502 ; https://learn.microsoft.com/en-us/microsoftteams/shared-channels
- [ ] Leave team: team … > **Leave** > confirmation; org-wide teams can't be left (admin only).
  Source: https://support.microsoft.com/en-us/office/leave-a-team-e481005d-3ec6-4694-b300-375472ba4076
- [ ] Leave private/shared channel: channel … > **Leave channel** (blocked for last owner).
  Source: https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/shared-channels
- [ ] Graph: `POST /teams/{id}/archive|unarchive`; `POST /teams/{id}/channels/{cid}/archive|unarchive`; `DELETE /teams/{id}/channels/{cid}`; `DELETE /groups/{id}`; restore deleted group via `POST /directory/deletedItems/{id}/restore` **[channel restore has no v1.0 endpoint – unverified]**.
  Source: https://learn.microsoft.com/en-us/graph/api/resources/team?view=graph-rest-1.0 ; https://learn.microsoft.com/en-us/graph/api/resources/channel?view=graph-rest-1.0

## 26. Channel header (open channel)

- [ ] Left: channel avatar (team picture) + channel name (click opens channel info card **[unverified]**), then tab strip (**Conversation**/**Posts**, **Shared**, other tabs, **+** Add a tab).
  Source: Threads PDF p.3-4 (screenshots) ; https://support.microsoft.com/en-US/teams/teams-channels/share-a-channel-with-people-in-microsoft-teams ("channel card")
- [ ] Right (threads layout screenshot order): Copilot/recap icon, sensitivity label pill (e.g. "Confidential"), **Meet now** (video icon) with ▾ (**Schedule meeting**), **Open threads** icon, channel info / participants icon, **More channel options** (…). Posts layout header similar without Open threads. **[icon identities except Meet now/Open threads: verify]**
  Source: Threads PDF p.3, p.7, p.11 ; https://practical365.com/teams-threaded-layout/
- [ ] Header … (More channel options): **See new posts at top/bottom** (posts layout), plus channel menu items (notifications, manage, edit, get link, email). **[full list: verify]**
  Source: https://support.microsoft.com/office/8f244ea6-235a-4dcc-9143-9c5b801b4992
- [ ] Search in channel / pop out channel / channel info pane (members, pinned, files): **[not covered by any fetched Microsoft doc; verify on winpc]**

## 27. Sensitivity, privacy, guests, external

- [ ] Team sensitivity label shown at creation and as a header pill; shared/private channel sites inherit the team label; classification editable via channel settings (team site description/classification).
  Source: https://support.microsoft.com/office/174adf5f-846b-4780-b765-de1a0a737e2b ; https://learn.microsoft.com/en-us/microsoftteams/shared-channels ; https://support.microsoft.com/en-us/topic/fda0b75e-5b90-4fb8-8857-7e102b014525
- [ ] Guests: added by owners via Add member using external email; guest permissions in Manage team > Settings > **Guest permissions**; guests can't create private channels, can't join via code/link, can't be added to shared channels; guests may see all channels in posts layout.
  Source: https://support.microsoft.com/topic/4756c468-2746-4bfd-a582-736d55fcc169 ; https://learn.microsoft.com/en-us/microsoftteams/private-channels ; https://learn.microsoft.com/en-us/microsoftteams/shared-channels ; https://support.microsoft.com/en-us/topic/9ee3c43f-8bbc-4fe2-89f3-88d618e8296c
- [ ] Private-channel meeting guests: external people joining a private channel meeting via link get temporary access to chat/files/whiteboard/notes/participants for the meeting only.
  Source: https://support.microsoft.com/office/de3e20b0-7494-439c-b7e5-75899ebe6a0e

## 28. Communities

- [ ] Communities are a Teams (free) / personal-account feature (Teams free on Windows 11), not part of the work/school Teams desktop chat-and-channels UI; out of scope unless the clone targets personal accounts. **[no work-account desktop doc found]**
  Source: https://support.microsoft.com/office/update-community-settings-in-microsoft-teams-free-fde7e4c1-6c64-47b5-9cb2-6980fb5b79a4 (via search summary)
