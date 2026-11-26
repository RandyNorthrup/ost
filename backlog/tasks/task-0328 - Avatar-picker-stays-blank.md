---
id: TASK-0328
title: Avatar picker stays blank
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T22:56:00Z'
updated_date: '2026-11-26T15:37:00Z'
labels:
  - bug
  - calls
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while capturing wiki screenshots (2026-11-25). The avatar picker (Video effects ▸ Avatars) stays blank.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The avatar picker shows what Teams shows for the account (avatars or Teams' empty/create state), verified against Teams on winpc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce the blank Avatars tab in a call and before joining
2. Compare with what the Avatars app lists for the account
3. Fix what keeps it blank
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Live (linuxlt, ost-test1): the pre-join Avatars picker and "Avatars" pane, and the call's Video effects and settings > Avatars tab (opened 9 times across runs, fresh and after other use) all showed the Avatars app's own panel: Your Avatar (None, Avatar 1), Edit my avatar, reactions, backgrounds, mood, camera; the renderer listed 1 avatar and 70 backgrounds. The blank tab of the wiki run could not be reproduced (its cause isn't known; that run also had the Avatars app make Chromium probe every camera node as it started, TASK-0334, which no longer happens).
- Teams on winpc (2026-11-26, ost-test1, a Meet now's pre-join, camera off, DOM read only, then Cancel; Teams put back on OneDrive): Effects and avatars > Avatars lists None, Avatar 1, Create More, then backgrounds None, Gold shimmer holiday, Red lights holiday, In the zone 1-3, and More avatar settings: the same as OST's pre-join picker (None, Avatar 1, Create More; the same backgrounds in the same order).
<!-- SECTION:NOTES:END -->
