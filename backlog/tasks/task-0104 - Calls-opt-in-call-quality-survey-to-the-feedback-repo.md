---
id: TASK-0104
title: 'Calls: opt-in call quality survey to the feedback repo'
status: To Do
assignee: []
created_date: '2026-11-11T01:52:00Z'
updated_date: '2026-11-11T16:51:00Z'
labels:
  - feedback
  - calls
dependencies: []
documentation:
  - docs/spec/feedback-and-help.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams' post-call 'How was the call quality?' as an opt-in (off by default); low ratings open Report a problem with the call's technical details (spec docs/spec/feedback-and-help.md §5).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings > Privacy has the opt-in, off by default
- [ ] #2 When on, the survey shows after calls as Teams' (How was the call quality? with Had issues / Good); Had issues with its Video / Screenshare / Audio reasons sends Report a problem to the feedback repo with media details and no participant names
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-11 reference, Teams desktop's post-call survey (captured on winpc after a meeting; CSS px in a 1280 x 680 window):
  - "How was the call quality?" 28/700 #424242; two 61.3 square buttons (0.67 #D1D1D1 edge, radius 4) with 50 px emoji images (personal-expressions …/emoticons/no and /yes /default/100_f.png), labels "Had issues" / "Good" 14 under them.
  - Good submits at once and shows "Thanks for the feedback!" / "We'll keep working on improving your experience." with a thumbs-up illustration.
  - Had issues: "What could've been better?" with tabs Video / Screenshare / Audio (radio buttons, 12/600, padding 5 12) and reason checkboxes in two columns. Video: The other side could not see my video; Video was ahead or behind audio; I could not see any video; The other side was too dark; Video kept freezing; Video blurring didn't work as expected; Image quality was poor; Video stopped unexpectedly. Screenshare: System audio didn't work as expected; I couldn't present my content; The other side could not see my presented content; The presented content kept freezing; I could not see any presented content; The presentation stopped unexpectedly; The image quality of the presented content was poor; There was a large delay in the presented content. (Audio's list wasn't captured.)
  - A privacy line with "Privacy statement", then Dismiss (96 x 31.3) and Send feedback (primary).
<!-- SECTION:NOTES:END -->
