---
id: TASK-0099
title: >-
  Feedback and help: OST's GitHub repo set up as Microsoft's feedback and help
  destinations
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T01:52:00Z'
updated_date: '2026-11-11T01:55:00Z'
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
- [x] #1 Issues and Discussions (Ideas, Q&A, Announcements) are enabled on the feedback repo
- [x] #2 Issue forms report-a-problem.yml and give-a-compliment.yml carry the same fields as Teams' form (text, details, logs, contact, version/OS/area) and can be prefilled from a URL
- [x] #3 Labels feedback, report-a-problem, compliment, feature-request exist; config.yml links Ideas, Q&A and Help
- [x] #4 SUPPORT.md and PRIVACY.md say what feedback shares and that issues are public
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Enabled Issues and Discussions on RandyNorthrup/ost (user approved 2026-11-10); Discussions come with Announcements, General, Ideas, Polls, Q&A, Show and tell.
- Labels feedback, report-a-problem, compliment, feature-request created.
- Issue forms (field ids what, details, logs, contact, area, version, os) and config.yml; SUPPORT.md, PRIVACY.md. GitHub reads issue forms from the default branch, so they are on main too.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The OST GitHub repo now receives what Teams sends to Microsoft.

- Issues and Discussions (Ideas, Q&A, Announcements) on RandyNorthrup/ost; labels feedback, report-a-problem, compliment, feature-request.
- .github/ISSUE_TEMPLATE: Report a problem and Give a compliment forms with Teams' form fields (prefillable by id), config.yml linking Ideas, Q&A and SUPPORT.md.
- SUPPORT.md and PRIVACY.md: what OST talks to, that it has no telemetry, and that feedback issues are public, with masked logs and no e-mail address.
<!-- SECTION:FINAL_SUMMARY:END -->
