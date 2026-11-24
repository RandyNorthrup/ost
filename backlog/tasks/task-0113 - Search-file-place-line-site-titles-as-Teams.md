---
id: TASK-0113
title: 'Search file place line: team and channel as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T03:35:00Z'
updated_date: '2026-11-14T05:16:00Z'
labels:
  - search
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the search page's Files results Teams' place line reads team › channel ('OST Test Team › General'). OST showed the site's address name and every folder, so team sites and Loop files looked wrong. Find Teams' rule and show the same.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Verified side by side with Teams on winpc for OneDrive, team-site and Loop results
- [x] #2 A file's place line reads team › channel by Teams' own rule (ChannelGroupId's team, else the joined team whose site or channel site is the file's, else the site address's name; the first folder under the library, else Shared Documents)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Teams never reads SiteTitle: search-app rr() names the team from ChannelGroupId, else the joined team (or private/shared channel) whose sharepointSiteUrl equals SpWebUrl, else SpWebUrl.split("/")[4]; the channel is group 5 of a regex on decodeURI(DefaultEncodingUrl), else "Shared Documents" (search.defaultChannelNameFileResults). Unredeemed files (Path null) get no place.
- The line is just two parts (component props teamName/channelName), which is why Teams drops ".appdata" on the Loop workspace row.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The search page's Files results now show the place line by Teams' own rule, exactly two parts: team › channel.

Changes:
- Team: the channel file's team (ChannelGroupId), else the joined team whose SharePoint site, or a private/shared channel's site, is the file's SpWebUrl, else the address's site name. This is Teams' search-app resolver; it never reads SiteTitle.
- Channel: the first folder under the library in the decoded DefaultEncodingUrl, else "Shared Documents". Files shared but never opened (no Path) get no place line.
- src/api/find.rs: Hit gains file_group_id and file_unredeemed (+ test). src/api/teams.rs: ListChannel gains site_url (sharepointSiteUrl).
- desktop/qml/SearchView.qml: filePlace rewritten. The --search-grid-test harness now logs each row's place.

Verified against Teams on winpc:
- "loop": OST Test Team › General; Secure Coast Network Solutions › General; x8FNO… › Copilot. Teams drops .appdata the same way.
- "Notebook": ost-test1_scnetsolutions_com › Notebooks; OST Test Team › OST Test Team Notebook. Capitalised by CSS as in Teams.

Tests: cargo test --lib find, teams.
<!-- SECTION:FINAL_SUMMARY:END -->
