---
id: TASK-0304
title: 'OneDrive Home layout as Teams: For you cards, Recent filters, place line'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T15:49:00Z'
updated_date: '2026-11-26T20:07:00Z'
labels:
  - onedrive
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' OneDrive Home shows For you cards (sp.RecentFileCollection.GetRecommendations) above the Recent list, the Recent filter pills (All, Word, Excel, PowerPoint, PDF, more filters), a Filter by name or person box, and each file's place under its name (My Files, someone's Files, a site). OST's Home lists the same files (TASK-0301) in the plain files table.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST's OneDrive Home shows the For you cards, Recent filter pills, filter box and place line as Teams does, measured against Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams' OneDrive Home on winpc (GetRecommendations, layout, pills, filter box, columns).
2. Read OneDrive's RecommendedStrip, pills and responsive column rules from its bundles.
3. Backend: api::recommended (For you cards), vis_type and activity lead/rest on rows.
4. OneDriveView: For you strip, Recent pills + More menu, filter box, Spartan list with place line.
5. Harness --onedrive-home-test; compare side by side with Teams.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- winpc 2026-11-26: Home's For you = {personal}/_api/sp.RecentFileCollection.GetRecommendations (verbose OData). OneDrive's RecommendedStrip: tiles clamp(floor((w+16)/(312+16)),3,8), 354 wide from 1464; RaaS Loop files left out; badge glyph map; button rules (activity link → Go to comment/task/Watch recording; Summarize/Recap when Copilot and meeting-prep or shared-by-someone-else and a Copilot file type; else Open). With "prefer: useSmartCache" the service answers a cached set without Loop/Whiteboard cards, so OST asks as Teams' own request does.
- Pills: All, Word, Excel, PowerPoint, PDF, More (OneNote, Lists, Videos, Loop, Whiteboard, PowerBI, Markdown, HTML) matching Visualization.Type; filter box (name, owner, activity).
- List: OneDrive's recentResponsiveBehavior (Name 300-500+, Opened 130-200, Owner 130-260, Activity 113-550) over card-8.33-45 → 337/167/167/150 at 876 as Teams; rows 56 with the place line (opens the folder); Activity two lines with the person in 600.
- Live on linuxlt vs winpc: For you shows Release tasks (Open), Weekly team sync (Open), 0.2.0 release checklist (Summarize), same order as Teams at that moment; Recent rows, place lines and columns match; Loop pill and "OST Test 3" filter work (--onedrive-home-test).
- Not built: page-level scroll (OST scrolls the list), Summarize asking Copilot the prompt (opens Copilot's page).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OneDrive Home now looks like Teams' Home: the For you cards, the Recent pills and filter box, and OneDrive's own list with the place line.

Changes:
- New `api::recommended`: For you from `sp.RecentFileCollection.GetRecommendations`, with OneDrive's RecommendedStrip rules (tile count and width, Loop-workspace files left out, badge glyphs, and the Open / Go to comment / Summarize / Recap buttons). Without `prefer: useSmartCache`, which answers from a cache that lacks the Loop and Whiteboard cards.
- Recent: pills All, Word, Excel, PowerPoint, PDF and More ▾ (OneNote, Lists, Videos, Loop, Whiteboard, PowerBI, Markdown, HTML), matching OneDrive's file type; the "Filter by name or person" box; Sort still applies.
- List: OneDrive's responsive columns (Name, Opened, Owner, Activity), 56 px rows with the place line (which opens the folder), and two-line Activity with the person in bold.
- New Fluent brand and file-type icons (NOTICE); docs/spec/onedrive-rows.md; harness `--onedrive-home-test`.

Tests: unit tests (cards, tile count). Live as ost-test1 side by side with Teams on winpc: the same cards in the same order with the same buttons, the same Recent rows and columns, and the pills and filter work.

Follow-up: TASK-0340 (column menus, page scroll, Summarize asking Copilot).

PR #20.
<!-- SECTION:FINAL_SUMMARY:END -->
