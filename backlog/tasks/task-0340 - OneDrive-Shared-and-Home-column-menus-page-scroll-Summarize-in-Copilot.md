---
id: TASK-0340
title: 'OneDrive Shared and Home: column menus, page scroll, Summarize in Copilot'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-26T17:05:00Z'
updated_date: '2026-11-27T00:51:00Z'
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
- [x] #1 Shared's and Home's column menus, page scroll and For you's Copilot buttons behave as Teams', verified on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' OneDrive Shared column menus, Home's scroller and For you Summarize (OneDrive's chat.aspx Copilot pane and its host messages) on winpc.
2. Shared: Name / Date shared / Shared by menus and sort; Home: one page scroller.
3. Summarize / Recap: host OneDrive's chat.aspx as Teams' OneDrive does (SDK messenger, updateDataSources, setPrompt, fetchAuthToken).
4. Harness --onedrive-columns-test [--summarize]; compare with Teams.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc 2026-11-26: Shared column menus are sort menus only (240 wide, 36 px items); Home's scroller is OneDrive's main area; Summarize opens OneDrive's chat.aspx in a 400 px pane over a 40% white veil (click closes), hosted over OneDrive's SDK messenger; Teams' configure options captured (chat settings + Fluent theme).
- Built: Shared sort menus and sort, Home page Flickable, OdspCopilotPane (host page of the SharePoint origin, isolated-world messenger, configure/showView/updateDataSources/setPrompt, fetchAuthToken via backend odspToken for Microsoft hosts), drive::copilot_source, harness --onedrive-columns-test [--summarize].
- Knowledge agent off (its host file tools are not offered; with it on the chat says "Some capabilities didn't load").
- Live: orders match Teams (Name A to Z identical); Summarize answers as Teams' pane. PR #26.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneDrive now has Shared's column menus, Home scrolls as one page, and For you's Summarize asks Copilot about that file in OneDrive's own Copilot pane, as in Teams.

Changes:
- Shared ▸ With you: Name ▾, Date shared ↓ ▾ and Shared by ▾ open OneDrive's sort menus (240 wide, 36 px items, A to Z / Z to A or Older to newer / Newer to older, with a check). The default is Date shared, newer to older. Home's and By you's headers have none, as in Teams.
- Home: For you, the pills and the list scroll together (OneDrive's main area is the scroller).
- Summarize / Recap: new OdspCopilotPane hosts OneDrive's chat.aspx as Teams' OneDrive does. It sits 400 px at the right with radius 12, over a 40% white veil that closes it on click.
  - A page of the same SharePoint origin frames the chat and speaks OneDrive's SDK messenger.
  - The host sends configure (Teams' chat settings and Fluent theme, captured), showView, updateInstruction, updateHeader, updateDataSources (the file's SharePoint ids, from Graph), updateChatInput, updateCustomPrompts and setPrompt 'Summarize "<file>"'.
  - fetchAuthToken is answered for Microsoft hosts only (backend "odspToken").
- Harness `--onedrive-columns-test [--summarize]`; docs/spec/onedrive-rows.md.

Tests: live as ost-test1 against Teams on winpc. Name A to Z gives the same order as Teams'. Summarize returns the same summary, styled as Teams'.

Differences:
- Teams' knowledge agent is off in OST, because its host file tools aren't offered.
- Shared by keeps the service order within one person.

PR #26.
<!-- SECTION:FINAL_SUMMARY:END -->
