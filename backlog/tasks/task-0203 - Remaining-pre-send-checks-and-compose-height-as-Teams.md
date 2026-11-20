---
id: TASK-0203
title: Remaining pre-send checks and compose height as Teams
status: In Progress
assignee: []
created_date: '2026-11-16T14:25:00Z'
updated_date: '2026-11-20T23:13:00Z'
labels:
  - desktop
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-0085 built Teams' pre-send checks that apply to an existing chat or post (spec docs/spec/messages-and-composer.md §18). Not built: the new-chat checks (recipients, group size, roster limit), pasted-picture upload checks, Loop and Nearby checks, and roaming of reply drafts in channel threads. OST's compose box also has no maximum height, so a very long message pushes the "too large" banner out of view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 New-chat, pasted-picture, Loop and Nearby checks block with Teams' wording as Teams does
- [x] #2 Compose stops growing at Teams' maximum height and scrolls, so banners stay in view
- [ ] #3 Reply drafts in channel threads roam as Teams' do when Teams' roaming setting is on
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-20 (chat agent):
  - Compose height (AC2), measured on winpc with 30 lines in OST group test: Teams' editor viewport (`compose-editor-viewport`, griffel class r1ymts1o) is `min-height: 3.8rem; max-height: 27rem` (270 px, the editor's padding included) with `overflow-y: auto`. OST's box now stops its text at 270 - 18 and scrolls it (wheel, and the caret kept in view); quotes, chips and cards stay put and the "too large" banner stays in view.
  - Pre-send checks (AC1), from Teams' evaluators (async-entry): the order is now Teams' 1–16. New: fluidComponentSyncing "Syncing... Please wait." and FluidPermissions "Checking permissions... Please wait." (compose Loop components); InlineImageContent wording hooks; noRecipient "The contact info doesn't look right. Enter the info again, then select from the list." (messaging:k6m4wdnk), notEnoughGroupParticipants "You need to add at least 2 people to start group chat." (k8jrb70dr) and exceedsMaxChatRosterSize ("You've hit / There's a {n}-person limit…", tmp_messages_exceedsMaxChatRosterSize_mf k39c3cbbu_mf; limit Teams' maxRosterSizeInGroupChat 250, picked people >= limit) in the new chat form. Nearby: Teams checks it only with People.enableAtNearbyMention (absent from this tenant's ECS, so off) and OST's mention picker has no @Nearby, so the check can't arise. Pasted pictures: OST's compose doesn't paste pictures inline yet, so their three banners have nothing to watch (open).
  - Reply drafts (AC3): a thread view now keeps its reply's draft as "{channel};messageid={post}" (Teams' -4.{post} reply chain) and roams it with innerThreadId `{channel};messageid={post}` when roaming is on; roamed reply drafts come back to that key.

- 2026-11-20 (chatB), measured on winpc: a pasted picture sits in Teams' box at its own size (data-tid image-with-loader, a blob: until sent). Sent ("OST TEST 203 pasted picture", OST group test): `<p><img src="{ams}/v1/objects/{id}/views/imgo" itemtype="http://schema.skype.com/AMSImage" itemscope="png" data-loading-state="success" data-inline-image="true" data-file-size="8410" width="320" height="180" alt="image" aria-description="has context menu" id="{id}" itemid="{id}" href="...imgo" target-src="...imgo"></p><p>text</p>`, amsreferences [id], properties.blurHash [{blurhash (4x3 components), imageId}].

- 2026-11-20 (chatB):
  - Pasted pictures built as Teams: Ctrl+V with a picture and no text on the clipboard puts it in the box at its own size (at most the box's width; the box takes its tall form), states initializing / failed ("Cannot paste this image. Try different source.") feed the InlineImageContent check; at send it is uploaded to AMS (image.png) and sent in Teams' inline form (`itemtype AMSImage itemscope png data-inline-image data-file-size width height alt "image" id itemid href target-src`), with amsreferences and properties.blurHash (4x3 BlurHash, api::blurhash). Checked live: OST's "OST TEST 203 pasted picture from OST" is stored exactly like Teams' "OST TEST 203 pasted picture" (same content form, blurHash, amsreferences); both messages deleted. `--paste-picture-test [--paste-picture-send]`.
  - Compose height (AC2) compared: Teams on winpc with 30 lines (typed over VNC) keeps the editor viewport at 270 px (scrollHeight 638, scrolling), box 340 to 653 in its 680 px window; OST stops its text at the same 270 and scrolls (`--compose-height-test`).
  - Nearby (AC1): there is no tenant setting for it. Teams offers @Nearby only with ECS People.enableAtNearbyMention, which isn't in this tenant's ECS (fetched 13:45 today: only presence enableNearbyInGroupChat / enableNearbyInOneOnOneChat and places enableNearbyMentionNewBadge, which are the roster's Nearby badges) and defaults to false outside Microsoft's own builds; the work-location policy it relies on was already on (tenant-changes). Nothing changed in the tenant, nothing to revert.
  - Reply drafts (AC3) roam with innerThreadId as built (OST_ROAM_DRAFTS); Teams' own roaming stays off for this tenant.

- 2026-11-20 merged. AC1: pasted pictures built (stored in Teams' exact form); @Nearby is behind a Microsoft-side feature flag not on for this tenant (no tenant setting exists), so its check cannot occur, as in Teams here. AC2 compared on winpc (270 px cap). AC3 built; Teams' own draft roaming is off for this tenant, so not yet comparable.
<!-- SECTION:NOTES:END -->
