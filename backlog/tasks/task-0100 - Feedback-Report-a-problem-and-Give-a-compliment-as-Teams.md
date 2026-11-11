---
id: TASK-0100
title: 'Feedback: Report a problem and Give a compliment as Teams'
status: To Do
assignee: []
created_date: '2026-11-11T01:52:00Z'
labels:
  - feedback
dependencies: []
documentation:
  - docs/spec/feedback-and-help.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings and more gets Feedback ▸ (Report a problem Ctrl+Alt+Shift+R, Give a compliment, Suggest a feature) and Help (F1) in Teams' places; the feedback form window reads as Teams' with OST/GitHub in Microsoft's place (spec docs/spec/feedback-and-help.md §1-2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings and more shows Help (F1) and Feedback ▸ with Teams' three items, icons and shortcuts; child windows' ··· has Report a problem
- [ ] #2 The form window matches Teams' measured layout and wording (Submit feedback to OST, What did you dislike?/like?, Add more details, Capture screenshot, Attach file, share logs, contact, footer, Submit/Cancel with Teams' required-field rules)
- [ ] #3 Submit opens the repo's prefilled GitHub issue form (title, text, version, OS, area, masked log lines if shared, contact answer); the screenshot is on the clipboard and other files' folder opens; Teams' thank-you state with the Finish on GitHub line shows
- [ ] #4 OST never posts anything itself and never puts the signed-in address in the issue
<!-- AC:END -->
