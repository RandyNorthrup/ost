---
id: TASK-0289
title: 'Work accounts: chats with personal-account people'
status: To Do
assignee:
  - '@t289'
created_date: '2026-11-25T15:26:00Z'
updated_date: '2026-11-28T00:31:00Z'
labels:
  - personal-accounts
dependencies:
  - TASK-0288
references:
  - docs/research/personal-accounts-features.md
  - docs/research/personal-accounts-protocol.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Personal-account users can already chat with work users when the tenant allows it. OST shows those 8:live: members without proper names, pictures or the External label Teams shows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a work account, a chat with a personal-account user shows their name, picture and Teams' External label, as Teams desktop does
- [ ] #2 A work user in OST can start a chat with a personal account by email, as in Teams, and messages flow both ways (ost-test1 with a personal test account)
- [x] #3 Buttons Teams disables for personal-account chats (calls, screen sharing, file limits) are disabled the same way in OST
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Live research: OST Test 2 / ost-test1 chats with OST Personal 2 (19:uni01_… thread, productThreadType OneToOneChat, memberProperties.relationshipState.inQuarantine), fetchTflProfiles (mris / invitersToThreads), externalsearchv3, Teams 26304 bundle (accept list / block list / interopconversationstatus, ExternalChatBanner, file rule w1, learn-more links).
2. Engine: identity::is_consumer_mri; directory short profiles resolve 8:live: via fetchTflProfiles (+ inviter email), Consumer pictures (profilepicturev2/8:live:…); chat list: OneToOneChat threads are 1:1 (peer, external, request flags); answer_chat_request (accept/block); new chat external search by address.
3. Desktop: External badge, banner, compose note, no files, disabled calls/screen share with Teams tooltip, chat request view (Block/Accept, preview), sender external glyph, picker External tag.
4. Tests, fmt, build on build boxes; live checks with ost-test1 (request from OST Personal 2), OST Test 2 (accepted chat) and a new chat by address; PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-27 live research (linuxlt, chat_get/mt_post probes): OST Test 2's chat with OST Personal 2 is 19:uni01_fjy3…@thread.v2, threadType chat, productThreadType OneToOneChat, productContext TFL, partnerName TFLGroupService, tenantid 0000…, members 8:live:.cid.ca2738c364862c6 (Admin) + OST Test 2 (User); memberProperties.relationshipState.inQuarantine false. ost-test1 has a pending request from OST Personal 2 (19:uni01_dsnp…, inQuarantine true).
- fetchTflProfiles (work MT token) {"mris":[…]} → resolvedUsers [{mri, skypeId, displayName "OST Personal 2", type TflConsumer, emailsInfo []}]; {"invitersToThreads":{mri: thread}} → emailsInfo [{address ost-personal2-0238@outlook.com, visibility Private}] (where Teams' request title gets the address).
- Teams 26304 bundle: Accept (1:1, work) = MT POST beta/userSettings/acceptlist/manage {"add":[mri]} then chat service conversation property interopconversationstatus = "Accepted"; Block = beta/userSettings/blocklist/manage {"add":[mri]} + "Blocked". Banner Learn more fwlink 2167727, disclaimer Learn more 2243561 (tfwTfwFedOneOnOneNewUILearnMoreUrl). chat-app file rule w1: work client + TflConsumer member → files off.
- externalsearchv3?includeTFLUsers=true without x-ms-client-caller answers 400 (UserDiscovery "Workload Unknown") for both personal addresses; to retry with the header.

- externalsearchv3 needs x-ms-client-type (and version): with them it answers 200 []. Both personal addresses give [] from ost-test1, OST Test 2 and OST Test 3, so Teams' work client would only offer the guest invite (not done: no guests).
- testpc2: opened the OST Personal 2 window (profile menu > Switch to account). Its Privacy > Manage how people can find you had the email switch OFF (TASK-0287 notes said it had been turned on); turned it ON at 13:37 PST to retry discovery later.

- Teams on testpc2 (OST Test 2, chat with OST Personal 2), UIA: call button "Calling isn't available in this chat." and "More call options" disabled; header More chat options = Open in new window | Schedule meeting | Mark as unread, Move to section, Mute, Copy link | Remove chat history (no Share screen); chat list row reads "Chat OST Personal 2 External unfamiliar"; the row's ··· menu adds Block. Window title "OST Personal 2 (External unfamiliar)".
- Build note: wslbuild keeps file mtimes, so a re-copied tree whose edits are older than the last build isn't rebuilt; touch the sources in the build command.

- Live (linuxlt, build of 14:10): OST Test 2 (OST_PROFILE=test2) chat with OST Personal 2: listed as "OST Personal 2", 1:1 (isGroup false), peer 8:live:…, O2 picture with presence, External badge, banner "OST Personal 2 is outside your org. …" + Learn more, call button disabled ("Calling isn't available in this chat."), "Replying to external participants." note, tools Format/Emoji/Loop/Actions (no Attach), external glyph after the sender's name.
- Live, ost-test1 (default profile) request from OST Personal 2: "OST Personal 2 (ost-personal2-0238@outlook.com) wants to chat with you", warning box with the Note and "preview their messages.", Block/Accept, disclaimer; preview shows the messages over Block/Accept. Accept → acceptlist/manage 200 and the chat service cleared inQuarantine (chat list request=false, presence Available). Sent "OST TEST 289 work reply to personal" from OST → seen in OST Personal 2's Teams window on testpc2 (UIA); OST Personal 2 replied "OST TEST 289 personal reply" from Teams → arrived in OST within ~25 s. Both ways verified.
- Fixes from the live run: the interopconversationstatus PUT is refused (400 ThreadPropertyNotAllowed; Teams keeps it local) → dropped; the disclaimer overlapped the buttons in an 800 px window → kept below them; "… added … to the chat." showed in the 1:1 thread → hidden as Teams does (1:1 threads known from the chat list); Share screen hidden (not disabled) in external chats as Teams' header menu; no Copilot button on a request.
- Work-side creation: POST /v1/threads with uniquerosterthread for an 8:live: member → 400 "Consumer users disallowed on uniquerosterthread"; Teams' worker uses fixedRoster + isStickyThread + chatFilesIndexId 2 → 201 19:uni01_…@thread.v2, and the same id again for the same roster (sticky). Made one such chat OST Test 3 ↔ OST Personal 2 while probing.

- Live (build of 14:46): OST Test 3 on testpc1 (WSL, --external-start harness = what the new chat form does after the search finds the person): start_external_chat → 201 the sticky 19:uni01_yjpb… thread (the probe's, returned again), first message "OST TEST 289 work starts a chat" sent; OST Personal 2's Teams showed it under Requests ("OST Test 3 (ost-test3@…) wants to chat with you", "To be safe, preview their messages." when the address is shared); accepted there and replied "OST TEST 289 personal answers OST Test 3", which reached OST Test 3 (chat service read). The work-started thread also lists productThreadType OneToOneChat.
- Teams' AcceptBlockSvg (727611 bundle, component K) written out as desktop/assets/illustrations/chat-request.svg (NOTICE.md) instead of a drawn stand-in.
- AC2 limit: externalsearchv3?includeTFLUsers=true answers [] for both personal addresses from ost-test1, OST Test 2 and OST Test 3, also ~1.5 h after OST Personal 2's email discoverability was switched on; with nothing found, Teams' work client itself offers only the B2B guest invite, which OST doesn't do (no guests created). So "start by email" is built as Teams does (search → External row → sticky thread with the first message) and verified from the found-person step on (by MRI), but not end to end from a typed address.
- Tests (testpc1/macbook): cargo test --lib identity:: api::directory:: api::chat:: api::search:: api::msgactions:: api::messages:: 102 passed; ost-desktop photo_target 1 passed; cargo fmt --check clean.

- PR #68 opened (branch task-0289-personal-chats).

- Coordinator follow-up: TASK-0366 (PR #62, open) autosuggest "where" line shows raw 8:live: ids from Substrate ToPreview.DisplayName; directory::short_profile_records / tfl_profiles is reusable there once #62 merges (comment on PR #68).

- Codex review: 4 findings (busy state across chats, short-window request pane, attachments into a new Teams free chat, edit box files) fixed in a13b4dd4 / b53a8ef6 (after rebase), threads answered. Rebased twice onto main (conflicts with the Mail photo owner, selection bar, reminders tests); rebased build + 107 lib tests pass on macbook; final live check as ost-test1 shows the accepted chat with no "added to the chat" line.

Built so far: everything in PR #68 (merged 2026-11-27): names/pictures via fetchTflProfiles, 1:1 chats, External UI, disabled calls/share/attach, Block/Accept chat requests (Accept verified live), messages both ways, new chat by Teams ID. Left for AC #2: starting a chat from a typed personal email address, end to end. Teams' external people search returns nothing for both test personal accounts (discoverability on for OST Personal 2 since 2026-11-27 ~14:00); retry when search finds them. Block was built from Teams' code but not run.

2026-11-27: lookup check with a real personal account (Randy's, search only, nothing sent): externalsearchv3 found it from ost-test1, OST Test 2 and OST Test 3 (TflConsumer, 8:live:<skype name> MRI, email visibility Public), and OST's To: box listed it with the External tag. So OST's email lookup works; AC #2 waits only on a test personal account whose email Teams' search returns (both test accounts' emails come back Private or not at all). Never test the chat itself with a real person's account.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Work accounts now handle chats with Teams free (personal-account) people as Teams desktop does.

Changes:
- Names and pictures for 8:live: members: fetchTflProfiles (mris; invitersToThreads for a request's private address), profilepicturev2/8:live:… (PhotoOwner::Consumer). identity::is_consumer_mri.
- Chat list: 19:uni01_ threads with productThreadType OneToOneChat (or sticky/unique roster) are 1:1 with peer, external and request flags; "… added … to the chat." hidden there.
- UI: External badge, outside-your-org banner, "Replying to external participants." note, external glyph after the sender; calls disabled with "Calling isn't available in this chat.", no Share screen, no Attach/clips (main box, edit box, new chat), no pasted pictures in chats the Teams free user started; no tabs.
- Chat requests: Teams' Block/Accept pane (its AcceptBlockSvg and strings, preview), scrolling in short windows; Accept/Block via userSettings/acceptlist|blocklist/manage.
- New chat by address: externalsearchv3?includeTFLUsers (with client type headers) → External row → sticky thread (fixedRoster + isStickyThread) made with the first message; never a guest invite.

Live: OST Test 2 and ost-test1 with OST Personal 2 (header/banner/compose/calls match testpc2's Teams), ost-test1 accepted OST Personal 2's request and messages went both ways; OST Test 3 started a chat by MRI, OST Personal 2 accepted it in Teams and replied. Tests: 107 engine lib tests, photo_target, CI (PR #68).

Not verified: starting from a typed address end to end (both personal addresses are undiscoverable from the work side: externalsearchv3 []; Teams itself would only invite a guest), Block live. Follow-up: TASK-0366 autosuggest can reuse directory::tfl_profiles for 8:live: names once PR #62 merges.
<!-- SECTION:FINAL_SUMMARY:END -->
