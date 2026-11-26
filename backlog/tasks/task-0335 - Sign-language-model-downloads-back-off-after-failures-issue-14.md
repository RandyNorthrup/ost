---
id: TASK-0335
title: 'Sign-language model downloads back off after failures (issue #14)'
status: To Do
assignee: []
created_date: '2026-11-26T15:10:00Z'
labels:
  - bug
  - calls
  - github-issue
dependencies: []
references:
  - https://github.com/RandyNorthrup/ost/issues/14
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub issue #14 (static review of v0.3.0): when sign language detection still needs its model, a failed preparation clears the in-flight flag and the next 500 ms tick starts another attempt, so a fast failure causes repeated requests and warnings while the feature stays on (desktop/src/backend.rs around L14920 and L16454 at bedf384d).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Failed model preparations retry with a bounded, growing backoff instead of every 500 ms; the backoff resets after a success or when the user turns the feature off and on again
- [ ] #2 Downloads stay one at a time with the pinned hash check; a unit test simulates repeated failures without contacting the model host
<!-- AC:END -->
