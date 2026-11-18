---
id: TASK-0104
title: 'Calls: opt-in call quality survey to the feedback repo'
status: To Do
assignee: []
created_date: '2026-11-11T01:52:00Z'
updated_date: '2026-11-18T14:02:00Z'
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

Built so far: Only Teams' Surveys switch under Privacy (synced like Teams', on by default, not connected to anything). The post-call survey isn't built. (Audit 2026-11-16)

- 2026-11-18 Teams' CQF read in its bundles (89637 mE/CreateCQFItems, components-calling-quality-feedback, 115569 thumbs UI; Griffel CSS resolved): sampling 0.1 for 1:1/group/meeting/share-from-chat, 0 PSTN/interop; ThumbsCombined shuffles categories and items and selects the first; Audio = 8 call items + 2 reliability, Video 8, Screenshare 8; Good sends at once, thank-you 3 s; unanswered 60 s; asked only while Surveys is on.
- Built: calling::quality_survey (items, sampling, shuffle, report details), CallQualitySurvey.qml (rating, What could've been better?, thanks with Teams' thumbs-up SVG), Settings > Privacy > Surveys card's "Ask me about call quality after calls" (off by default, desktop.json callQualitySurvey, usable while Surveys is on), backend callQualitySurvey/callQualityDetails; Send feedback opens Report a problem (area Call quality) with the reasons as its text and the kind, length, reason ids and Call health values as details (no names). OST_CQF_ALWAYS / --cqf-always for tests.
- Verified live on linuxlt (ost-test1, a solo test meeting, deleted after): cqfset2-cqfset-off/on (opt-in off by default, on, put back), cop1/cop2-cqf-rate, -issues, -ticked, -feedback (Report a problem filled in, closed unsent), -thanks; cqfg2-cqf-thanks (Good). Nothing was posted.
<!-- SECTION:NOTES:END -->
