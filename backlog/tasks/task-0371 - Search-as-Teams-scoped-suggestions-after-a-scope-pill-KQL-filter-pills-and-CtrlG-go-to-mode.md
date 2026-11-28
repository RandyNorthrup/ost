---
id: TASK-0371
title: >-
  Search as Teams: scoped suggestions after a scope pill, KQL filter pills and
  Ctrl+G go-to mode
status: Done
assignee:
  - '@t371'
created_date: '2026-11-27T20:58:00Z'
updated_date: '2026-11-28T03:02:00Z'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-0366 (title bar search suggestions). Teams desktop (winpc, 26304): picking a scope pill (e.g. Files) puts is:Files in the box, shows the chosen pill with x plus its nested filter pills (Files: from:, in:, filetype:; Messages: from:, in:, has: per ECS autosuggest.nestedFiltersConfig) and lists that domain's suggestions ("Suggested files", ECS domainScopingConfig zqCount/qfCount); typing a person puts a from:<person> pill first (People-centric search). The suggestion rows' hover actions (meeting Chat/Join/Recap, person search icon, chat pop-out) and the Ctrl+G go-to mode (Tip row) are also Teams'. TASK-0366 ships the pills as is:<Tab> scopes that open the results tab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Picking a scope pill shows Teams' scoped flyout: chosen pill with x, nested filter pills, the domain's suggestions; checked side by side with Teams desktop
- [x] #2 from:/in:/filetype:/has: filter pills pick a person, place or type as Teams does and narrow the suggestions and results
- [x] #3 Rows' hover actions (meeting Chat/Join/Recap, person search, chat pop-out) work as in Teams
- [x] #4 Ctrl+G and the Tip row enter Teams' go-to mode (Type a chat or channel) with its suggestions
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture Teams desktop (winpc 26304, ost-test1, CDP read-only): each scope pill's request and flyout, the nested KQL pills (from:/in:/filetype:/has:), their pickers and QueryAnnotations/Filters, the PCS from:<person> pill, rows' secondary actions, Ctrl+G go-to mode (local list, powerbar.goto fallback).
2. Engine (src/api/autosuggest.rs): scoped/KQL/go-to requests (Teams' bodies, flights, domain=), arrange_kql into Teams' groups and texts; unit tests.
3. Desktop: backend searchSuggestKql; TitleBar parses the box (is:, picked KQL tokens, the open picker), keeps the annotations, Ctrl+G go-to mode (/goto chip, Type a chat or channel); SearchSuggest scoped pill row, pickers, domain headings and Press Enter texts, hover actions per row kind, go-to list; Enter hands the KQL filters to the results page.
4. Build on testpc1, live-check side by side with winpc Teams, PR with TASK-0376.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (winpc Teams desktop 26304 as ost-test1, CDP read-only, 2026-11-27):
  - Scope pill: box "is:Files ", POST suggestions?scenario=powerbar&setflight=TurnOffMPLSuppressionTeams[,EnableTeamsChannelDomainPowerbar|,EnableMessageImageSearch]&domain=File|Message|TeamsChannel|Chat|Event; one entity (File/Message 10, TeamsChannel 8, Chat 10, Event 10, Images = Message 18) with QueryAnnotations [Domain (Is) + picked filters]; words typed add People Size 1 (the from:<person> pill). Meetings send the words only.
  - Flyout: chosen pill (filled, ×) + nested pills (Files from:, in:, filetype:; Messages from:, in:, @Mentions, Has attachments; picked ones first), "Suggested files/messages/channels/group chats/meetings", "Recent images"; typed: no heading, "Press Enter to view all files/…".
  - from: picker: People 5 (no PersonalContact), KqlKeyword From, rows "from:<name>", first picked, ghost rest of name + Tab; in: picker: Chat 2, Channel 2, Team 2, People 5 (KqlKeyword In); filetype: local "Select a file type" (Excel, Loop, PDF, PowerPoint, Text file, Word; Filter FileType term = ExtensionType Pdf/Word/...); has: tokens has:@Mentions / has:Attachments = Filter HasMentions / HasAttachments True.
  - Typing a person: from:<person> pill first (PeopleAsText); picking it: box "from:OST Test 2 ", pills minus Channels, Chat 5/File 3/Message 5/People 1: top hit, Recent messages + "See more messages from X", Group Chats.
  - Row actions (hover or pick): person Open in new window, Show Contact Card, All results from X; group chat Open in new window; channel Copy link, Open in new window; file Copy link; meeting Chat with participants (+ Join Meeting now/within 15 min, Meeting Recap past; bundle 158357); messages none.
  - Ctrl+G: "/goto" chip, "Type a chat or channel", no pills/footer, local list (people first, then group/meeting chats and channels), first row with a focus ring; nothing local: POST ?scenario=powerbar.goto (People 5, Chat 5, Team 3, Channel 4), then only "Press Enter to view all results".

- Built: autosuggest kql_request/arrange_kql/fetch_kql (scoped, pickers, from:<person>, go-to remote) + 3 unit tests; backend searchSuggestKql; TitleBar parses the box (is:, kqlPicks tokens, open picker), brand-coloured tokens, ghost + Tab, Clear query, /goto chip, go-to local list; SearchSuggest pill list, pickers, headings, Press Enter texts, row actions; Enter hands the filters to the results page (search_page now runs on filters alone); harness --search-steps.
- Live on testpc1 WSLg (profile t366 = ost-test1, same account as winpc Teams), compared with the winpc captures: Files (Suggested files, same 10), from: picker (same 5 for "ost", ghost " Test 2" + Tab), from:OST Test 2 picked (pill with photo, Press Enter to view all files), filetype: (6 types, "p" → Loop, PDF, PowerPoint; filetype:Pdf pill), in: (Release planning, Design review, OST layout test, OST test channel, OST Test 2), Enter → Files tab with PDF / In / Person set and the PDF result; Messages (Suggested messages, from:, in:, @Mentions, Has attachments; @Mentions → the one mention), Channels, Group chats, Meetings, Images (2 images, from:OST Test 2 pill when typing) as Teams; "ost test" → from:OST Test 2 pill first; picked → from:OST Test 2 with Messages/Files/Group chats/Meetings/Images, top hit, Recent messages, Group Chats as Teams.
- Row actions live: person Open in new window (opened the 1:1 chat window), Show Contact Card (profile card), All results from; channel Copy link + Open in new window; meeting Chat with participants (opened the meeting chat) and Meeting Recap on a past one.
- Go-to live: Ctrl+G path (gotoMode) shows /goto, Type a chat or channel, people then chats/channels, first row ringed; "ost" lists 5 people + 5 conversations; nothing local ("zzqxv") asks powerbar.goto and shows Press Enter; Enter opened OST Test 3's 1:1 chat.
- Differences left: "release" with has:@Mentions shows nothing (the service answers empty for Teams too; Teams adds a local hit); go-to's named group chats have no member line (OST's chat list has no members); the go-to order is OST's recency, not Teams' affinity scores.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The title bar search now has Teams desktop's scoped mode, KQL filter pills, row actions and go-to mode.

What Teams does (winpc, Teams 26304, ost-test1, captured read-only over CDP): a scope pill writes is:<Domain> and asks the suggestions service for that domain alone (domain=…, Teams' sizes and flights, QueryAnnotations); Files and Messages add nested pills (from:, in:, filetype: / @Mentions, Has attachments) that open pickers or add filters; typing a person offers a from:<person> pill; rows show secondary actions; Ctrl+G is a /goto mode over local chats, channels and people.

Changes:
- src/api/autosuggest.rs: kql_request (scoped, from:/in: pickers, from:<person> with no scope, powerbar.goto), arrange_kql (Teams' groups, headings, pcs person), annotation shapes; refactored people requests; tests.
- backend: searchSuggestKql (images fetched as Recent images'); search_page runs on filters alone.
- TitleBar: the box parsed into scope, picked filter tokens (brand-coloured) and an open picker; ghost completion and Tab; Clear query; /goto chip and Type a chat or channel; Enter hands the filters to the results page (Person, In, File Type, More).
- SearchSuggest: pill list (chosen, nested, from:<person>), pickers with the first row picked, Suggested … headings, Press Enter to view all …, row actions (Open in new window, Show Contact Card, All results from, Copy link, Chat with participants, Join Meeting, Meeting Recap), go-to list with its focus ring.
- Main: Ctrl+G opens go-to mode; pop-out, contact card, join and recap handlers; --search-steps harness.

Live: testpc1 WSLg (ost-test1) against the winpc captures: every scope, the three pickers, picked filters, results with the filters, the from:<person> pill, row actions and go-to mode (see notes).

Differences left: Teams adds local hits the service doesn't return (has:@Mentions + words); go-to has no member line for named group chats and orders by recency instead of Teams' affinity scores.
<!-- SECTION:FINAL_SUMMARY:END -->
