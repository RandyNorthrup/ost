---
id: TASK-0099
title: >-
  Feedback and help: OST's GitHub repo set up as Microsoft's feedback and help
  destinations
status: To Do
assignee: []
created_date: '2026-11-11T01:52:00Z'
labels:
  - feedback
  - help
dependencies: []
documentation:
  - docs/spec/feedback-and-help.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams sends feedback to Microsoft and help to Microsoft's sites; OST sends them to the OST GitHub repo (spec docs/spec/feedback-and-help.md §6). Needs the repo owner's go-ahead for repo settings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Issues and Discussions (Ideas, Q&A, Announcements) are enabled on the feedback repo
- [ ] #2 Issue forms report-a-problem.yml and give-a-compliment.yml carry the same fields as Teams' form (text, details, logs, contact, version/OS/area) and can be prefilled from a URL
- [ ] #3 Labels feedback, report-a-problem, compliment, feature-request exist; config.yml links Ideas, Q&A and Help
- [ ] #4 SUPPORT.md and PRIVACY.md say what feedback shares and that issues are public
<!-- AC:END -->
