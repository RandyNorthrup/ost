---
id: TASK-0039
title: 'Desktop: channel Page tab'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06T04:53:00Z'
updated_date: '2026-11-09T15:28:00Z'
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

- 1:1 pass: Teams renders the Page with Loop component code inside its own window (no URL), which OST can't host. OST shows Loop's real page with Loop's app frame hidden (top bar, side panel, tour, template gallery), edge to edge, and draws Teams' parts natively: the header row (page icon from its favicon, name, Shared locations, Copy component, See who has access) and the insert row (Table, Bulleted list, Checklist, Task list, Voting table, ...).
- The insert row types Loop's "/" commands as real key presses through a native KeyTyper item (Qt key events to OST's own window); synthetic page events don't open Loop's menu. Tested on scratch copies in the test account's OneDrive (since recycled): each button inserts its block.
- See who has access opens Loop's sharing menu; Loop's own toolbar stays laid out (invisible) so its menus anchor.

- 2026-11-09: the Page tab was blank. Its embedded view was switched off on 11-06 (commit 7b048c6, before the 11-07 decision to embed what Teams embeds) and never restored. It is now restored: Page shows the channel's Loop page in place from the tab's content URL.
- On a machine where OST's web profile isn't signed in yet (linuxlt), the tab shows Microsoft's sign-in in place. Teams has SSO for this; OST needs that profile signed in once.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Channels show Teams' Page tab between Shared and Notes.

Changes:
- Channel tabs come from Graph (`/teams/{id}/channels/{id}/tabs?$expand=teamsApp`): Posts, Shared, then Page (pinned after Shared, as Teams does), Notes and app tabs.
- Page shows the tab's Loop page in place, as Teams embeds it. Loop's own app frame is hidden; Teams' parts are drawn natively:
  - the header row (page icon, title);
  - the insert row, which types Loop's "/" commands as real key presses through a native KeyTyper;
  - See who has access.
- Only https Microsoft hosts are loaded, in OST's web profile (one-time Microsoft sign-in, shared with Whiteboard and Clipchamp).

Tests: `--open-chat=<General of Secure Coast> --tab=Page`; each insert button tried on scratch copies in the test account's OneDrive (since recycled).
<!-- SECTION:FINAL_SUMMARY:END -->
