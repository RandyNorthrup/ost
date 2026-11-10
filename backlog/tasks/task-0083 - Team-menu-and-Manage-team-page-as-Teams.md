---
id: TASK-0083
title: Team menu and Manage team page as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T20:42:00Z'
updated_date: '2026-11-10T03:36:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams has a ··· menu on each team row (Hide all channels, Add member, Add channel, Manage team, Get link to team, Manage tags, Leave/Edit/Delete team…; docs/spec/chat-list-and-header.md §5.6) and a Manage team page (Channels, Members, Pending requests, Settings, Analytics, Apps, Tags). OST's team rows have no menu and there is no Manage team page; Manage channel's All Channels and Analytics across channels lead there in Teams.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each team row has Teams' ··· menu with Teams' items, conditions and order
- [x] #2 Manage team opens Teams' page in the conversation's place with its tabs, each measured against Teams
- [ ] #3 Manage team ▸ Analytics shows the team's analytics (Summary with Active guests, Engagement, charts; Analytics across teams) and Manage channel's All Channels / Analytics across channels open it
- [ ] #4 Verified side by side with Teams on winpc in OST Test Team
- [x] #5 Manage channel ▸ Settings for a channel other than General shows Teams' channel moderation and settings (verified with a test channel made by Add channel in OST Test Team)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Team row ··· menu (TeamMenu.qml) with Teams' items and actions: Hide all channels (provisioning service), Copy link, Manage team. Then Add member, Add channel, Manage tags, Archive, Leave and Delete, each with Teams' dialog.
2. Manage team page (ManageTeam.qml) with Teams' seven tabs:
   - Channels (filters, sort, search, rows, row menu);
   - Analytics (team dashboard);
   - then Members, Pending requests, Settings, Apps and Tags, each measured and wired to Teams' APIs.
3. Manage channel's All Channels / Analytics across channels open the team's analytics.
4. Non-General channel settings, verified with a test channel created through Add channel in OST Test Team.
5. Verify each piece side by side on winpc.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Piece 1:
  - Team row ··· (TeamMenu.qml): Hide all channels (Teams' confirm, PUT {teamsAndChannelsProvisioningService}/team/{thread}/hide, captured), Copy link (team link captured from the winpc clipboard), Manage team.
  - ManageTeam.qml: header with the seven tabs, the Channels tab (pills All / Shown for you / 4 more, Sort, Search channels, rows with Last active as date-fns formatDistance, Hide/Show, the row menu = channel menu without posts order and Hide) and Analytics (AnalyticsView team scope: All Channels, Active guests, Analytics across teams).
  - Manage channel's All Channels and Analytics across channels open it.
  - CSA fields added to the team list: last_active, channel_type, archived, shared_in, deleted_channels, team description.

- Piece 2: Add channel. Teams' Create a channel (CreateChannelDialog.qml, measured): name rules with the check, description, the type dropdown (Standard / Shared / Private tiles), Recommend for Standard, the Layout cards (Threads first).
  - Create posts as Teams does (captured twice): POST {mt}/beta/teams/{team}/channels, then favorite; with Recommend, setDefaultChannel and lastTimeFavorited.
  - Opened from the team menu and Manage team ▸ Add channel; the new channel opens.
  - Verified: OST created "OST test channel 3" and Teams lists it. Teams made "OST test channel" and "OST test channel 2" (recommended) for the non-General work.
  - Manage team rows show Recommended, and Last active falls back to the creation time, as Teams does.
  - Private and Shared creation still need Teams' member step: next piece.

- Piece 3: channel owner items for channels other than General (Teams' menu, measured): Recommend for everyone / Stop recommending, Archive channel (Teams' dialog with the SharePoint read-only box), Delete channel (Teams' dialog with the files link). An archived channel gets Teams' short menu (Open in new window, Manage channel, Copy link, Restore channel, Delete channel).
  - APIs captured:
    - archive/unarchive on the provisioning service (its token resource https://templates.teams.microsoft.com, from Teams' config), with ?setSpoSiteReadOnlyForMembers=true;
    - DELETE {mt}/beta/teams/{team}/channels/{channel};
    - PUT/DELETE {mt}/beta/teams/{channel}/setDefaultChannel.
  - Fixed: Hide all channels used the middle-tier token (401). It now uses the provisioning token and was verified from OST, then everything was shown again.
  - Verified from OST (--channel-owner-test): restore, archive, restore, recommend, unrecommend, create, delete, hide all, show. Create errors map to "Channel name is already taken." when the server names a conflict (a deleted channel's name too).

- 123c364: non-General Manage channel ▸ Moderation (dropdown On/Off, moderators summary + hover card, who can post, member permissions) and Add or remove moderators (team profile search, roster PUT). Verified both ways with Teams on "OST test channel" (left Off). Adding/removing an actual moderator could not be exercised: OST Test Team has no non-owner member; wire taken from Teams' bundle.

- 6951ab6: team menu Add member with Teams' Add members dialog (searchV2 addToTeam, groups via Graph transitiveMembers, roles, guests). Add request (bulkUpdateRoledMembers / inviteAndAddGuest) taken from Teams' bundle, not run live (no new tenant members allowed).

- 840a413: Manage tags (Tags tab, tag page, Create/Edit/Add people/Delete dialogs, CSA tag API; PATCH is v2). Verified both ways on OST test tag (description set in Teams, cleared from OST, left empty).

- d960629: team Archive/Restore, Leave, Delete with Teams' dialogs. Archive+restore verified live (team back in Teams' list); last-owner Leave refused by the service as Teams expects; Delete not run.

- 00b91b0: Manage team Members tab (roster, tags, role dropdown, remove); matches Teams' tab for OST Test Team. Role change / remove not run (only member is the last owner).

- a3e53ab: Pending requests tab (findJoinRequests, accept/deny, empty state matches Teams). No request could be raised to test the list.

- 2962d22: Manage team Settings tab (details + Edit team + Change picture, permissions, @mentions, team code, fun stuff, tags). Verified: permission toggle, description edit (Teams shows it after restart), team code shown in Teams then removed. Team picture: a Remove+Save made in Teams during research changed it to Teams' pale initials; OST then uploaded Teams' server default (solid magenta, the original look); Teams desktop still shows its cached pale one.

- 2bf52c5: Manage team Apps tab (aggregated team entitlements; Copy link as Teams; Remove; Create an outgoing webhook). All seven Manage team tabs now built; AC #2 checked.

- Private channels: Create a channel (Private) goes through the provisioning service (channelsWarmup + channels POST) and then shows the "Add members to the {channel} channel" step; Delete channel on a private channel uses the provisioning DELETE with OID:{substrateGroupId}@{tenant}. OST created and deleted "OST private test 2"; Teams' Manage team list confirmed both. The member step's Add isn't run (OST Test Team has no other members). Spec §5.6.8.
<!-- SECTION:NOTES:END -->
