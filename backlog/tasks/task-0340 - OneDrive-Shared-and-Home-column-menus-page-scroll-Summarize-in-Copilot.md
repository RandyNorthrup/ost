---
id: TASK-0340
title: 'OneDrive Shared and Home: column menus, page scroll, Summarize in Copilot'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T17:05:00Z'
updated_date: '2026-11-26T20:48:00Z'
labels:
  - onedrive
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0304/0320 built OneDrive's Spartan list. Teams also has the column header menus (Name ▾, Date shared ↓ ▾, Shared by ▾; sort and filter), scrolls Home's page as a whole (For you scrolls away), and For you's Summarize / Recap this meeting open Copilot beside the files with the prompt asked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Shared's and Home's column menus, page scroll and For you's Copilot buttons behave as Teams', verified on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' OneDrive Shared column menus, Home's scroller and For you Summarize (OneDrive's chat.aspx Copilot pane and its host messages) on winpc.
2. Shared: Name / Date shared / Shared by menus and sort; Home: one page scroller.
3. Summarize / Recap: host OneDrive's chat.aspx as Teams' OneDrive does (SDK messenger, updateDataSources, setPrompt, fetchAuthToken).
4. Harness --onedrive-columns-test [--summarize]; compare with Teams.
<!-- SECTION:PLAN:END -->
