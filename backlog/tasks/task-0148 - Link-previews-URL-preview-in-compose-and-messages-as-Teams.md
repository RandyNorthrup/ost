---
id: TASK-0148
title: Link previews (URL preview) in compose and messages as Teams
status: Done
assignee:
  - '@claude'
created_date: '2026-11-15T04:40:00Z'
updated_date: '2026-11-15T22:10:00Z'
labels:
  - messaging
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Teams turns a pasted or typed link into a preview card in the compose box and sends it with the message; recipients see the card. It is one of the 'Optional connected experiences' (Settings > Privacy): when that is off, Teams makes no previews. OST has no link previews yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Typing or pasting a link in compose shows Teams' preview card, which can be removed before sending
- [x] #2 The sent message carries the preview as Teams sends it, and Teams on winpc shows it
- [x] #3 Messages from Teams with link previews show the preview card in OST
- [x] #4 With Optional connected experiences off, no previews are made, as Teams
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read Teams' URL-preview code (agent spec) and measure its card in compose and messages on winpc
2. Engine api::url_preview: fetch (urlpV2 richInfo/info), links property, received parsing, removal
3. Compose: AutoLink, first-link watch, card, X; send hook and send-time fetch
4. Messages: card, sender Remove; privacy and policy gates
5. Verify live with Teams on winpc
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Measured on winpc: compose card 460x96 (picture 120x96, body 340 with 8/12 padding), message card 6 under the text, bubble 14.6 under it.
- Wire format captured from Teams (OST TEST 158): properties.links with previewenabled/preview{previewurl,title,description}.
- The urlpV2 GTM is https://us-prod.asyncgw.teams.microsoft.com/urlp; richInfo answers with the skype token.
- Verified live: OST TEST 159 sent from OST showed Teams' card on winpc. Remove from OST cleared it in Teams (previewenabled false). With Optional connected experiences off, OST made and showed no previews; the setting was restored.
- Not built: app link unfurling (GitHub/Wikipedia app cards), now in the left-out list.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Link previews as Teams, in compose and in messages.

Changes:
- New `api::url_preview`:
  - Teams' URL preview service (`urlpV2` `v1/url/richInfo`, falling back to `info`) and Teams' validity rule (two of picture, title, description).
  - Exclusions (Teams links, mailto, SharePoint/OneDrive).
  - The `properties.links` wire format; reading received previews (first link only, enabled, valid).
  - Removing a preview from a sent message (`PUT …/properties?name=links`). Unit tests.
- Compose:
  - Teams' AutoLink (Space/Enter/paste, its URL rules); the rich-text state gains `link` and an `unlink` op so the following space stays outside the link.
  - The first link's preview is fetched 125 ms after typing and shown as Teams' card (UrlPreviewCard.qml, measured) with Remove URL Preview.
  - It is sent with the message, or fetched at send within 3 s when compose had none yet.
- Messages: Teams' card under the text (the bubble sized as Teams), the whole card opens the link, and the sender's X removes the preview.
- Gates: Optional connected experiences and the messaging policy's allowUrlPreviews (read at sign-in); no previews in notes to self or edits.
- docs/spec/url-previews.md; harness --link-preview-test (with -send, -remove-only, -privacy).

Tests:
- cargo test --lib (529 passed).
- Live: Teams' own preview message renders in OST. OST's sent preview (OST TEST 159) renders in Teams on winpc. Remove from OST clears it in Teams. Privacy off: no previews, then the setting was restored.

Not built: app link unfurling for sites with Teams apps (listed as left out).
<!-- SECTION:FINAL_SUMMARY:END -->
