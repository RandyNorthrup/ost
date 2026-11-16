---
id: TASK-0200
title: Link cards from installed apps and apps that need sign-in, as Teams
status: To Do
assignee: []
created_date: '2026-11-16T11:48:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0168 shows Teams' app card for links to sites whose Teams app allows anonymous use (Wikipedia Search, YouTube in this tenant). Not covered yet: installed apps (composeExtension/queryLink, no installed test app here) and apps whose card asks you to sign in first (GitHub's "Show Preview"), which keep the plain preview in OST.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A link handled by an installed app shows its card via queryLink, as Teams
- [ ] #2 An app card that asks to sign in (GitHub's Show Preview) signs in and then shows the card, as Teams
<!-- AC:END -->
