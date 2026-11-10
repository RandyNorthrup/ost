---
id: TASK-0086
title: Create team and Join team as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T04:20:00Z'
updated_date: '2026-11-10T05:09:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Your teams and channels has Teams' Create team split button (Create team, Join Team). Teams opens its Create a team flow (team name, description, privacy, first channel, sensitivity; templates) and the Join team gallery (search public teams, Join with a code). OST has neither, so the button does nothing. The tenant rule allows no new teams and no joining real teams, so creating/joining can only be verified up to the request Teams would send.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Create team opens Teams' Create a team flow, measured against Teams, and creating a team sends Teams' request
- [x] #2 Join Team opens Teams' join gallery (search, public team cards, Join a team with a code), measured against Teams
- [x] #3 Verified side by side with Teams on winpc without creating or joining a team
- [x] #4 More create team options opens Teams' Create team page: templates with their details and Customize channels, From another team with its copy choices, and From group
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research Teams' Create a team, More create team options, Join a team on winpc and their requests in Teams' code.
2. API module team_create.rs (bodies, templates, clone, groups, suggested/find/join).
3. QML: CreateTeamDialog, CreateTeamPage, JoinTeamPage; wire from Your teams and channels.
4. Harness; compare with Teams; spec.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Implemented Create a team (scratch / template / copy kinds, team type page, Customize channels, discard question), the Create team page (templates with details, From another team, From group) and Join a team (suggestions, search, join, join with a code).
- Requests from Teams' code with this tenant's flags (no provisioning v2 for scratch/template/group; template-service clone v2 on). Nothing created or joined (tenant rule): bodies are unit-tested.
- Teams' Incident Response icons rendered black in Qt (clipPath with <use> outside <defs>); cached SVGs are now rewritten (src/svg.rs), checked with Qt 6.10.
- Verified every view side by side with Teams on winpc (--create-team-test). Spec §5.6.10.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Adds Teams' Create team and Join a team flows behind Your teams and channels' Create team button.

Changes:
- src/api/team_create.rs: create from scratch (mt beta/teams/create), templates and their details (provisioning teamtemplates), create from a template (provisioning team), copy a team (provisioning groups/{id}/clone/v2), your groups and create from a group (mt migrateGroup), suggested/find/join/join-by-code; bodies as Teams builds them.
- CreateTeamDialog.qml (scratch, template and copy kinds, team type page, first channel naming, Customize channels, discard question), CreateTeamPage.qml (From template / From another team / From group), JoinTeamPage.qml (Teams for you, search, team cards, join with a code).
- src/svg.rs: Teams' template SVGs that clip with <use> are rewritten so Qt draws them.
- Rail shows no app chosen on these pages, as Teams.

Tests:
- cargo test team_create, svg (372 lib tests pass)
- --create-team-test harness on linuxlt compared with Teams on winpc; nothing was created or joined (tenant rule).

Risk: the create/join requests could not be sent here; they follow Teams' code for this tenant's flags.
<!-- SECTION:FINAL_SUMMARY:END -->
