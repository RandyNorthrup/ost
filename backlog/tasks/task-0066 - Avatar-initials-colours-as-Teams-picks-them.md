---
id: TASK-0066
title: Avatar initials colours as Teams picks them
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T03:20:00Z'
updated_date: '2026-11-09T07:33:00Z'
labels:
  - desktop
  - parity
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OST colours initials avatars with its own name hash. Teams (Fluent colorful avatar) picks the colour differently: for example, in the Transcript pane and the gallery, OST Guest 1 is yellow in Teams and blue in OST. People whose photo OST fetches from Teams' photo service already get Teams' colour; guests and anyone drawn locally don't.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Locally drawn initials avatars use the same colour as Teams for the same person (checked against winpc for an org user, a guest and a group)
- [x] #2 The colour rule is documented in docs/spec with its source in Teams' code
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research: Teams draws no initials for people; every person avatar is an <img> from the middle tier's picture service. Directory users: profilepicturev2/8:orgid:{oid} (OST already used it). Guests: beta/users/defaultProfilePictureV2?displayname={name} (seen in winpc's People pane for OST Guest 1).
- OST blanked guests' ids and drew its own initials (wrong colour). Now photo_target maps 8:teamsvisitor ids to PhotoOwner::Named, fetched by name; QML passes guests' ids (captions, transcript, People pane, chat bubble, report dialog).
- Groups: Teams' grey #949494 circle, already as measured.
- Verified live: OST Guest 1 is yellow in OST's People pane, as in Teams (was blue). Spec: docs/spec/avatars.md.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Guests' avatars now use the picture Teams shows for them.

Teams draws no initials itself: people's avatars come from the middle tier's picture service, and guests (no directory id) are asked for by name through defaultProfilePictureV2. OST did that for directory users but drew its own initials for guests, in different colours.

Changes:
- api::directory::photo: PhotoOwner::Named fetches defaultProfilePictureV2?displayname=… (HR196x196).
- backend photo_target: 8:teamsvisitor ids map to Named; cache key "named-…".
- QML: guests' ids are passed to Avatar in captions, the Transcript pane, the People pane, chat bubbles and the report dialog.
- docs/spec/avatars.md: the rule and its source in Teams' code.

Tests: desktop photo_targets_accept_only_object_ids (guest case added); live meeting join: OST Guest 1 yellow as in Teams.
<!-- SECTION:FINAL_SUMMARY:END -->
