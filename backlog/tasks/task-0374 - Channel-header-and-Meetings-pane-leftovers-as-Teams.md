---
id: TASK-0374
title: Channel header and Meetings pane leftovers as Teams
status: To Do
assignee: []
created_date: '2026-11-27T23:15:00Z'
labels:
  - desktop
  - channels
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0364 (PR #60). Still different from Teams: the people popover's Agents and bots lists every bot in the team (Teams listed only Forms; filter unknown) and People shows the team roster instead of Teams' recent channel contributors; the channel Meetings pane has no per-meeting ··· menu, no custom From/To range, an Organizer list instead of people search, is 360 wide (Teams 419 at the same window size), and opens a meeting's details only for meetings in your own calendar; the pop-out channel window still has the old Meet now header; and builds crash at startup with OST_QML_DIR set on the default profile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Agents and bots and People in the channel people popover list what Teams lists (rule researched and documented)
- [ ] #2 The channel Meetings pane matches Teams: per-meeting ··· menu, custom From/To range, Organizer people search, Teams' width, and details for any listed meeting
- [ ] #3 The pop-out channel window has the same meeting button and menu as the main window
- [ ] #4 OST starts with OST_QML_DIR set on the default profile
<!-- AC:END -->
