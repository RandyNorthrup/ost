---
id: TASK-0122
title: 'Details pane bell: turning item notifications back on'
status: To Do
assignee: []
created_date: '2026-11-12T17:48:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OneDrive's Details pane bell posts ActivityLogger/FeedbackDirect (NotificationPreferenceChanged). With OST's SharePoint token 'None' works but 'Comments' (on) fails with 'Failure : Action could not be performed' (System.Net.WebException); Teams' cookie+digest request succeeds. Find the request or token that turns notifications on (docs/spec/details-pane.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OST can turn an item's activity notifications back on, verified in Teams
<!-- AC:END -->
