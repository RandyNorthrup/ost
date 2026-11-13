---
id: TASK-0122
title: 'Details pane bell: turning item notifications back on'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-12T17:48:00Z'
updated_date: '2026-11-13T16:58:00Z'
labels:
  - files
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OneDrive's Details pane bell posts ActivityLogger/FeedbackDirect (NotificationPreferenceChanged). With OST's SharePoint token 'None' works but 'Comments' (on) fails with 'Failure : Action could not be performed' (System.Net.WebException); Teams' cookie+digest request succeeds. Find the request or token that turns notifications on (docs/spec/details-pane.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OST can turn an item's activity notifications back on, verified in Teams
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-13: with SharePoint healthy again, FeedbackDirect "Comments" succeeds with OST's bearer token, with or without an X-RequestDigest (tested with sp_post: None → Comments → Comments, each confirmed by v2.1 notificationPreferences). The 11-12 failure was the outage.
- Added --bell-test: Details on ost-share-test.txt, bell off, reload (off), bell on, reload (on); passes on linuxlt and ends on Comments as it began.
- Fixed "Unable to assign [undefined]" warnings for non-comment cards in DetailsPane.

- Verified in Teams on winpc: the Details pane bell for ost-share-test.txt reads "Notifications for item activity. Select to turn off notifications" (on) after OST turned it back on.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Details pane bell turns item notifications back on.

The request OST already sends works once SharePoint is healthy: the 12 Nov failure came from that day's Microsoft 365 outage, not a missing digest or cookie. No code change was needed for the request itself.

Changes:
- New --bell-test harness (off, reload, on, reload) to keep it verified.
- Spec (details-pane.md) corrected.
- DetailsPane: no undefined author bindings on activity cards.

Tests: --bell-test on linuxlt (before on → off → reloaded off → on → reloaded on); state confirmed through v2.1 notificationPreferences.
<!-- SECTION:FINAL_SUMMARY:END -->
