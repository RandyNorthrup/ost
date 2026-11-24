---
id: TASK-0100
title: 'Feedback: Report a problem and Give a compliment as Teams'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-11T01:52:00Z'
updated_date: '2026-11-11T02:12:00Z'
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
- [x] #1 Settings and more shows Help (F1) and Feedback ▸ with Teams' three items, icons and shortcuts; child windows' ··· has Report a problem
- [x] #2 The form window matches Teams' measured layout and wording (Submit feedback to OST, What did you dislike?/like?, Add more details, Capture screenshot, Attach file, share logs, contact, footer, Submit/Cancel with Teams' required-field rules)
- [x] #3 Submit opens the repo's prefilled GitHub issue form (title, text, version, OS, area, masked log lines if shared, contact answer); the screenshot is on the clipboard and other files' folder opens; Teams' thank-you state with the Finish on GitHub line shows
- [x] #4 OST never posts anything itself and never puts the signed-in address in the issue
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- FeedbackWindow.qml (Teams' form, measured), src/feedback.rs (issue URL with Teams' form fields, masked log tail fitted to GitHub's URL size, title), native clipboard image set/save, backend feedback_issue_url / feedback_link / feedback_dir / paste_clipboard_image / request_feedback (+ feedback_requested signal for child windows).
- Settings and more: Help (F1) and Feedback ▸ (Report a problem Ctrl+Alt+Shift+R, Give a compliment, Suggest a feature) with Teams' icons; child windows' ··· has Report a problem.
- Verified on linuxlt with --feedback-test (menu, empty/filled forms, screenshot capture, URL and masked logs). Help (F1) opens the Help app until TASK-0103.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Feedback ▸ Report a problem and Give a compliment work as Teams', sent to OST's GitHub.

- Settings and more gains Help (F1) and Feedback ▸ (Report a problem, Ctrl+Alt+Shift+R; Give a compliment; Suggest a feature) in Teams' places with its icons; child windows' ··· has Report a problem.
- The feedback window copies Teams' form (measured): Submit feedback to OST, What did you dislike?/like?, Add more details with Capture screenshot / Attach file / drop / paste, the share-logs and contact questions, the footer (truthful: the issue is public), Submit/Cancel with Teams' required answers.
- Submit opens the repo's issue form filled in (title, text, area, version, OS, contact; masked log lines if shared, fitted to GitHub's URL limit) and puts the first picture on the clipboard; OST posts nothing itself and never adds the e-mail address.

Tests: feedback:: unit tests (URL fields, log fitting, masking, file names, titles); --feedback-test on linuxlt.
<!-- SECTION:FINAL_SUMMARY:END -->
