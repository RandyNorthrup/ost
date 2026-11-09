---
id: TASK-0074
title: Send-side bandwidth estimate for Call health's Teams send limit
status: To Do
assignee: []
created_date: '2026-11-09T10:13:00Z'
labels:
  - desktop
  - meetings
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Call health's 'Teams send limit' (network-sent-bw-estimate) is Teams' send-side bandwidth estimate. OST has no send-side estimator, so the value shows '--'. A transport-wide/GCC-style estimator would fill it and could also drive the video encoder's bitrate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Call health's Teams send limit shows OST's live send-side estimate in a call
- [ ] #2 The video encoder's bitrate follows that estimate
<!-- AC:END -->
