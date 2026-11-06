---
id: TASK-0039
title: 'Desktop: channel Page tab'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-06T16:28:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams channels have a Page tab (after Shared) that OST doesn't show yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A channel shows Page between Shared and Notes, with the channel's page as Teams shows it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Channel tabs now come from Graph (/teams/{id}/channels/{id}/tabs?$expand=teamsApp): Posts, Shared, then Page (pinned after Shared, as Teams does), Notes and any app tabs.
- Page shows the tab's Loop page (its SharePoint .loop link, https and Microsoft hosts only) in place with OST's web profile, without the app header. It reaches Microsoft's sign-in, a one-time step for the user in OST's web profile (shared with Whiteboard and Clipchamp).
- Checked with --open-chat=<General of Secure Coast> --tab=Page.
<!-- SECTION:NOTES:END -->
