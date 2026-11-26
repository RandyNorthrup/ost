---
id: TASK-0336
title: 'Feedback says what is sent before opening GitHub (issue #15)'
status: To Do
assignee: []
created_date: '2026-11-26T15:10:00Z'
labels:
  - privacy
  - help
  - github-issue
dependencies: []
references:
  - https://github.com/RandyNorthrup/ost/issues/15
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #15: the feedback dialog prefills a GitHub issue through the browser URL, so the typed text and the contact choice reach GitHub when the page opens, even if the user never submits. PRIVACY.md documents this; the dialog should say it too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Before the browser opens, the dialog tells the user that the text they typed and their contact choice are sent to GitHub when the page opens, even if they don't submit the issue
- [ ] #2 The user can instead copy the text and open a blank issue form; logs and attachments stay local as now
- [ ] #3 PRIVACY.md, OST's Help article and the wiki say the same
<!-- AC:END -->
