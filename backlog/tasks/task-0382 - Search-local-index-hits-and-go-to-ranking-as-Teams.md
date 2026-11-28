---
id: TASK-0382
title: 'Search: local-index hits and go-to ranking as Teams'
status: Done
assignee:
  - '@t382'
created_date: '2026-11-28T05:37:00Z'
updated_date: '2026-11-28T08:00:00Z'
labels:
  - desktop
  - search
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-0371 (PR #79). Teams adds hits from its own local index that the suggestions service doesn't return, so OST shows nothing where Teams shows a few: has:@Mentions with words typed, and is:Messages with an in:<channel> filter. In go-to mode, named group chats lack Teams' member line, and the order is by recent activity rather than Teams' relevance ranking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 has:@Mentions with words and is:Messages with in:<channel> list the same hits as Teams desktop for the same account (from OST's own cached messages where Teams uses its local index)
- [x] #2 Go-to mode shows named group chats with Teams' member line and orders results as Teams does
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research on winpc Teams 26304 (CDP read-only) and in its bundles: where the has:@Mentions / in:<channel> hits come from; go-to ranking and member line.
2. Engine: message backfill request/merge (autosuggest.rs) like Teams; UKB affinity scores parsed and scaled as Teams; chat list horizon/member title/member names; channel horizon.
3. Desktop: backend backfill after the suggestions, loadGotoAffinity; TitleBar go-to list with Teams' ranking, interleave and member line; SearchSuggest place line from the chat's member title.
4. Build on testpc1, live-compare with winpc Teams, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (winpc Teams 26304.1207 as ost-test1, CDP read-only; bundles 813599/886630/158357/r_data-resolvers-search-suggestions):
  - The "local index" hits are not local: with the Messages pill, when the suggestions service brings back fewer than the 10 messages asked for, Teams also asks the search service (POST searchservice/api/v2/query, scenario powerbar, QueryType PowerbarTypeAheadMsg, size 25, topResultsCount 10) with the box's filters as the search page writes them ("mentions:<oid> AND NOT (isClientSoftDeleted:TRUE) release", "clientthreadid:<channel> AND NOT (…) *", "hasattachment:yes AND …", "NOT (…) <mail> release" with a People queryAnnotation) and lists the messages the suggestions lack after theirs (deduped by InternetMessageId, REMOTE_FIRST). Captured: has:@Mentions alone (1 suggestion + 2), with "ubuntu" (1), release has:Attachments (3 + 3), in:OST test channel (0 + 6), with "test" (6), from:OST Test 2 release (6 + 5), plain "signed" (backfills too); Files and unscoped boxes don't.
  - Its x-client-flights are the search page's minus nwShortenCaptionsForTeamsCtrlfSearch, FakeConversationUXFlight, EnableFileFiltersViaKQL; with the page's set has:Attachments found 3 instead of 6.
  - Teams' real local index (activity-feed prefetch cache, reply-chain cache) is used only when the search service fails (SERP local fallback); not needed for these hits.
  - Go-to: an.A local list: top-N people that match (first 2, People 2), conversations (group, meeting chats, channels/teams, own chat; 1:1 chats as people once typed) ranked by gotoRelevanceType WEIGHTED_AFFINITY + affinityScoresModel NORMALISED_ZSCORES (prod defaults): match bucket (holds the words as typed 2, prefix only 4) scaled, recency 0.97^hours since your consumption horizon, affinity (UKB userknowledgebase/v1.0/{upn}/teams/affinityscore, Score -1 dropped, z-score scaled 0…1; own chat 1; new chats the kind's mean), weights 33/33/34; enableReorderGotoSuggestions: two more top people after each three conversations; Total 10. Named group chats: title = topic, subtitle = chatTitle.shortTitle (useChatDataFromSubstrate); roster match on members for group and meeting chats.
- Built: autosuggest wants_backfill/backfill_body/backfill_messages/merge_backfill/fetch_backfill (Teams' powerbar flights via find::search_raw_flights), affinity_scores/fetch_affinity; chat list horizon, created, memberTitle, memberNames, alone, left (named group chats' members read with the unnamed ones', cached by roster); channels horizon_ms; backend backfill after the suggestions, loadGotoAffinity + gotoAffinityJson; TitleBar go-to rewritten to Teams' ranking; SearchSuggest: a group chat message's place is the chat's member line; no Press Enter for Messages with only in:; unit tests.
- Live, testpc1 WSLg (profile t366 = ost-test1) against winpc Teams the same hour: has:@Mentions (same 3, same order), + ubuntu (1), release has:Attachments (same 6, same order), in:OST test channel (same 6, same order), + test (same 6, same order), from:OST Test 2 release (same 11, same order), place lines "Release planning | OST and OST Test 3" as Teams.
- Go-to live: "release" identical (3); "3", "ost", "test", empty: same rows in the same order except (a) Teams lists the empty, hidden, never-read unnamed chat "OST and OST Test 3" high although its horizon is 0 and UKB has no score for it (every UKB row this account gets has Score -1, which Teams drops too) — not explained by Teams' code from the data it stores; OST ranks it by its 0 recency, below the ten; (b) the second top person: OST's top-N (peoplecache, as the People row) has ost-personal2-0238 second, Teams' stored top-N has OST Guest 02 (its store from an earlier refresh); (c) meeting chats aren't matched by their members (OST doesn't read meeting rosters for ~150 meeting chats), so "test" lacks OST AUDITB 1.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Search now has the hits Teams adds to the Messages pill, and go-to mode ranks and labels chats as Teams does.

What Teams does (winpc, Teams 26304, ost-test1, CDP read-only, plus its bundles): the extra hits are not from a local index. With the Messages pill, when the suggestions service returns fewer than the 10 messages asked for, Teams also asks the search service (v2/query, PowerbarTypeAheadMsg, 25, with the box's filters as KQL) and appends the messages the suggestions lack. Go-to ranks conversations by match, how recently you read them (consumption horizon) and UKB affinity (weights 33/33/34), shows two top people first and more after every three conversations, and gives a named group chat its member line.

Changes:
- src/api/autosuggest.rs: wants_backfill / backfill_body / backfill_messages / merge_backfill / fetch_backfill; affinity_scores / fetch_affinity; tests.
- src/api/find.rs: search_raw_flights, with Teams' powerbar flights (the search page's flights find fewer has:Attachments hits).
- src/api/chat.rs, teams.rs: chats' horizon, created, member title and names (named group chats' members read with the unnamed ones', cached by roster), alone, left; channels' horizon_ms.
- backend: the backfill after the suggestions; loadGotoAffinity + gotoAffinityJson.
- TitleBar: go-to list rewritten to Teams' ranking, member match, interleave, hidden chats and unlisted meeting chats included, self row's address; no Press Enter for Messages with only in:.
- SearchSuggest: a group chat message's place line is the chat's member line; go-to member line highlighted.

Live (testpc1 WSLg, ost-test1, against winpc Teams): has:@Mentions, + ubuntu, release has:Attachments, in:OST test channel (+ test), from:OST Test 2 release: same hits in the same order, same place lines. Go-to "release" identical; empty, "ost", "3", "test" the same apart from the gaps in TASK-0385 (meeting chats matched by members, Teams' stored top-N, an empty unnamed chat Teams ranks high without horizon or score).

Tests: cargo test -p teams-cli --lib (1106 passed); clippy -D warnings clean (teams-cli, ost-desktop with test-harness).
<!-- SECTION:FINAL_SUMMARY:END -->
