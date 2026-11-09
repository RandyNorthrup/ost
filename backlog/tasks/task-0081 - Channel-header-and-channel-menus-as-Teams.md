---
id: TASK-0081
title: Channel header and channel menus as Teams
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T17:38:00Z'
updated_date: '2026-11-09T19:34:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' channel header has a Meet now split button and More channel options, and every channel row in the chat list has the same ··· menu (measured on winpc, 2026-11-09: See new posts at top | Open in new window | Manage notifications ▸, Move to section ▸, Hide | Edit channel, Manage channel, Copy link, Get email address, Workflows). OST's channel header has neither and channel rows have no menu (docs/spec/chat-list-and-header.md §7.7-7.8).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Channel header: Meet now split button (Meet now / Schedule a meeting) with Teams' disabled reasons; Find and Channel details only on Posts
- [ ] #2 More channel options and the channel row's ··· show Teams' items in Teams' order
- [ ] #3 Each item acts as Teams': See new posts at top, Open in new window, Manage notifications, Move to section, Hide, Edit channel, Manage channel, Copy link, Get email address, Workflows
- [ ] #4 Verified side by side with Teams on winpc in OST Test Team
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (winpc, 2026-11-09):
  - Meet now opens the meet-now pre-join (heading "Microsoft Teams meeting", an editable title "Meeting in \"<channel>\"") and starts an adHocMeeting on the channel; the service posts the meeting in the channel.
  - ··· items:
    - See new posts at top: user property enableChannelsV2 = "false"; a different layout with a top "Post in channel" card and newest first.
    - Manage notifications: channelNotificationSettings {allNewPosts, tag, channelTeam, dskNotif} plus alerts, and a Customize dialog.
    - Hide: properties favorite / isGeneralChannelFavorite "false", member interest NotInterested (Show reverses it).
    - Edit channel dialog: name, description, Layout Threads/Posts.
    - Manage channel page: Settings and Analytics.
    - Get email address: {mt}/beta/channels/{id}/email with GET/POST/PUT/DELETE and allowedSenders.
- Done so far: Meet now split (Meet now / Schedule a meeting) and the meet-now pre-join. Verified live: OST's channel Meet now made the same "Meeting in \"General\" ended" post in Teams.
- Channel header: Find and Channel details (PanelRightExpand) show only on Posts, with no people button.

- More channel options and the channel row ··· (ChannelMenu.qml): Teams' items, order and icons, with the Manage notifications flyout. Customize, Edit channel and Get email address dialogs were built from measurements and Teams' own strings.
- Backend: api::channels (notifications, follow all, Hide/Show, Edit, email, new posts at top/bottom, channel link) and the channel_action invokable. The team list now carries notify, owner, layout and description.
- Verified live in OST Test Team:
  - notifications All, then back to @mentions;
  - Hide (Teams then lists General in italics) and Show (back to normal);
  - Copy link is byte-identical to Teams' clipboard (text and HTML);
  - the email dialog shows the channel's address.
- Fixed: a hidden General is the team's isGeneralChannelFavorite (captured), not the channel's isFavorite.
- Left: See new posts at top (layout), Open in new window, Manage channel (Settings / Analytics), Workflows, and a hidden channel's italic row and "See all channels".

- Open in new window (ChannelWindow.qml): Teams' 588 x 493 channel window. Its header has Meet now (icon and chevron), Find and ···; the compact channel posts (cards 30 in, names over times, ChannelPosts.compact); Post in channel. The backend keeps the channel live under its own "win:" key. Verified: a post sent from the window while the main window showed another chat appears in Teams.
- Research for the rest:
  - Workflows embeds automations.teams.cloud.microsoft/webapps/workflows/prod/home (renderMode=modal, subContext=channelworkflows, channel and team params) under a native header.
  - Manage channel Settings: Channel details, plus Moderation (General: spaceAdminSettings.userSettings.generalChannelSetting 0/1/2, written back whole).
  - Analytics: {mt}/beta/analytics/teams/{team}/channels/{channel}/summary-timeseries.
<!-- SECTION:NOTES:END -->
