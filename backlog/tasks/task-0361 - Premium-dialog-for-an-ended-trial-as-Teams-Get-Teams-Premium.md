---
id: TASK-0361
title: Premium dialog for an ended trial as Teams (Get Teams Premium)
status: To Do
assignee: []
created_date: '2026-11-27T18:15:00Z'
labels:
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-0357. After a Teams Premium trial has ended and the trial licence is gone (isTPManagement false), Teams' ··· > Get Teams Premium opens its licence-request modal (TeamsPremiumModal Xi: panelType premiumLicenseRequestModal when the trial isEnded; content is not the 'You've got Teams Premium!' licensed page). OST opens its 'licensed' page there. Research the modal's content from Teams' components-teams-premium-dialog bundle (do NOT click Request a license: with ECS enableTeamsPremiumAutoLicenseRequest it sends a request to the admin) and build it. Also check whether Teams hides the title-bar Premium pill at narrow window widths (Dse's second argument from the more-options button state) and match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Get Teams Premium after an ended trial opens the same dialog content as Teams desktop, checked side by side without sending a licence request
- [ ] #2 Title-bar Premium pill shows or hides at the same window widths as Teams desktop
<!-- AC:END -->
