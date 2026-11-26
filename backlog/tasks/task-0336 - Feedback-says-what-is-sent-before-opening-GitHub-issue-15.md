---
id: TASK-0336
title: 'Feedback says what is sent before opening GitHub (issue #15)'
status: Done
assignee:
  - '@issues'
created_date: '2026-11-26T15:10:00Z'
updated_date: '2026-11-26T18:13:00Z'
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
- [x] #1 Before the browser opens, the dialog tells the user that the text they typed and their contact choice are sent to GitHub when the page opens, even if they don't submit the issue
- [x] #2 The user can instead copy the text and open a blank issue form; logs and attachments stay local as now
- [x] #3 PRIVACY.md, OST's Help article and the wiki say the same
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FeedbackWindow: Submit shows a review step (Teams' type and buttons) saying GitHub gets the title, text and contact answer when the page opens, even without Create; shows them; buttons Open filled-in form / Copy text and open a blank form / Back.
2. Backend: blank flag -> template-only issue URL, text on the clipboard; ddv records which.
3. Suggested-reply feedback note says the same timing.
4. Fix PRIVACY.md, docs/help report-a-problem, docs/spec/feedback-and-help.md, docs/desktop.md, feedback.rs docs; --feedback-test walks both paths logging URLs instead of opening a browser.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed at 8722149f:
- src/feedback.rs:96-125 issue_url puts the title (from the text), the text and the contact answer in the new-issue query string.
- desktop/qml/FeedbackWindow.qml:61-67 submit() opens that URL right away; nothing before it says GitHub gets the text when the page opens.
- PRIVACY.md:174-187 says it; docs/help/troubleshoot/report-a-problem.md:24 says "Nothing leaves your device until you select Create" (wrong); src/feedback.rs:7 module doc says the same.
- The suggested-reply feedback (desktop/qml/Conversation.qml:3808-3815, SmartReplyFeedback.qml) uses the same prefilled URL.

AC3: PRIVACY.md and the Help article are updated in this PR; the wiki text was handed to the session that updates the wiki, so AC3 stays open until the wiki says the same.

- 2026-11-26: wiki updated (Help-and-feedback, Privacy-and-data; wiki 654466f), so AC #3 is met.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The feedback window now says what GitHub receives, and when, before the browser opens, and offers a blank form instead (issue #15).

Cause: Submit opened the prefilled new-issue URL at once; the title, text and contact answer are in the URL, so GitHub got them as the page opened, even without Create. Help even said nothing left the device until Create.

Changes:
- `desktop/qml/FeedbackWindow.qml`: Submit shows a "Before your browser opens" step in the form's own type and buttons: what GitHub receives (title, text, contact answer) and that it gets them as soon as the page opens; that screenshots, files, details and logs stay local; buttons Open filled-in form / Copy text and open a blank form / Back (Escape goes back). The thank-you text matches the path taken. The footer says Submit shows this first.
- `src/feedback.rs`: `blank_issue_url` (template only); docs corrected. `desktop/src/backend.rs`: `blank` in the report JSON opens that URL and puts the text on the clipboard; `feedbackIssueTitle` for the preview; View Diagnostic Data records `prefilled`.
- `SmartReplyFeedback.qml`: its note says the same timing before Send.
- PRIVACY.md, docs/help/troubleshoot/report-a-problem.md, docs/spec/feedback-and-help.md, docs/desktop.md updated. The wiki text is in the PR/report for the wiki session.
- `--feedback-test` now walks both paths and logs the URLs instead of opening a browser.

Tests and live check:
- `the_blank_issue_form_holds_nothing_typed` and the existing feedback tests pass.
- linuxlt, ost-test1, `--feedback-test`: Report a problem review then filled-in URL (title, text, contact only), Report a problem blank URL `?template=report-a-problem.yml` with the text on the clipboard, Give a compliment review and filled-in URL, Suggest a feature's Ideas URL; screenshots of each step checked. No browser opened, nothing submitted.

Follow-up: TASK-0337 (Help's GitHub article links use a removed branch).
<!-- SECTION:FINAL_SUMMARY:END -->
