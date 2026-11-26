---
id: TASK-0304
title: 'OneDrive Home layout as Teams: For you cards, Recent filters, place line'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T15:49:00Z'
updated_date: '2026-11-26T17:05:00Z'
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
