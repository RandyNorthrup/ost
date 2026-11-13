---
id: TASK-0130
title: 'Cloud file picker and attachment card: the rest of Teams'' details'
status: To Do
assignee: []
created_date: '2026-11-13T21:53:00Z'
labels:
  - desktop
  - files
  - messages
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
What TASK-0085's Attach left of Teams' cloud file picker and compose card (docs/spec/messages-and-composer.md §17, measured 2026-11-13): the picker's command bar (New folder, Upload, view switch), People as Teams (OneDrive's collaborators, GetCollaboratorsAsStream, and their files), Media's date headings and layout and zoom controls, Teams' shared-folder icons, Home rows Teams adds without an open time (the OST Test Team Notebook), the card's Link settings (its description opens them, with 'People currently in this chat'), the Attach popover's suggestion rows (unmeasured: ost-test1 has none), and the attach menu in a post's thread view (PostThread).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The picker's command bar, People, Media and folder icons match Teams'
- [ ] #2 The attachment card's link description opens Teams' Link settings and the choice applies to what is sent
- [ ] #3 Suggested files in the Attach popover look as Teams draws them (measured with an account that has suggestions)
- [ ] #4 A post's thread view offers the same Attach popover
<!-- AC:END -->
