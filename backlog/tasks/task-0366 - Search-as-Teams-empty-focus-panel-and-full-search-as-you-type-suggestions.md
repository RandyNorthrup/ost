---
id: TASK-0366
title: 'Search as Teams: empty-focus panel and full search-as-you-type suggestions'
status: Done
assignee:
  - '@t366'
created_date: '2026-11-27T18:19:00Z'
updated_date: '2026-11-28T00:03:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope A), which compared Teams (desktop for some items, Teams on the web teams.microsoft.com/v2 as ost-test1 for the rest; the web app is what new Teams desktop runs) with OST main on linuxlt. Each acceptance criterion is one verified gap; its full entry (what Teams does, what OST does, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditA.md under its number, screenshots in audit/shots-A/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A-16: Search box shows nothing when focused with an empty query; fixed to match Teams desktop, checked side by side
- [x] #2 A-17: Search-as-you-type suggestions only list chats; fixed to match Teams desktop, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture what Teams desktop (winpc, ost-test1, Teams 26304) shows and requests: zero-query GET and typed POST to substrate suggestions?scenario=powerbar, its DOM measurements, ECS autosuggest settings, the bundles' converters (chat, file, event, message, text) and actions.
2. Engine: src/api/autosuggest.rs (Teams' requests and headers; arrange() into Teams' groups: top hits from LayoutHints, Recent messages (5 + See more), People, Files, Channels, Teams, Group Chats, Meetings, Recent images; zero query: People row (top-N) + Suggestions); unit tests.
3. Desktop: backend searchSuggest -> suggestJson; SearchSuggest.qml flyout (pills, groups, rows, footer tip / Press Enter, Send feedback), TitleBar wiring (focus asks zero state, typing debounced, arrows/Enter, actions), Main handlers.
4. Build on testpc2, live-check side by side with Teams desktop, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (winpc Teams desktop 26304 as ost-test1, CDP read-only): focusing the empty box sends GET substrate suggestions?scenario=powerbar&query= (plus Teams' top-N people cache); typing sends POST ?scenario=powerbar&setflight=EnableMessageImageSearch,EnableTeamsChannelDomainPowerbar with People/File/Chat/Team/Channel/Text/Message/Event/App requests (PeopleCentricSearch). Group order from ECS autosuggest.suggestionsGroupOrder; 5 messages (unscopedDomainConfig); flyout max height 70% of the window; texts and rules from Teams' converters (file Created/Shared by, channel files Team > Folder, meeting attendee lines, message prefixes, names list formatter).
- Built src/api/autosuggest.rs (requests, arrange, 6 unit tests), backend searchSuggest/suggestJson, SearchSuggest.qml, TitleBar wiring (focus, debounce, arrows/Enter, picks), Main handlers; harness --search-test=<text> [--search-pick=<kind>].
- Live on testpc1 WSLg (profile t366 = ost-test1, same account as winpc Teams): empty focus shows pills, People row (OST Test 2, Guest 02, Guest 01, OST Test 3 ...) and Suggestions (Weekly team sync event, chats, Release tasks.loop, Loop paragraph.loop OST Test Team > General), Tip and Send feedback, matching Teams. "release": history "release notes", Release planning / OST 0.2.0 release (OST and OST), Release tasks.loop (Created by OST Test 1), Release-notes-0.3.pdf (Shared by OST Test 3), Recent messages (5 + See more), Files (0.2.0 release checklist.loop), Meetings (Release go/no-go: You invited OST, OST +1 others; Release readiness review: OST invited you), Press Enter footer - same items and texts as Teams. "ost test": person top hits with OST-TEST2 alias lines, "OST Test 3 in all results", history, Just me, Ask Copilot, messages, People, Files (Shared by), Channels, Group Chats, Meetings, Recent images - same groups as Teams.
- Picks checked live: person -> 1:1 chat, chat -> chat, channel -> channel, message -> chat at message, See more -> results Messages tab, recent search -> results, "X in all results" -> results, meeting -> calendar details.
- Not done here (follow-up TASK-0371): pill scoped mode with nested KQL pills and domain suggestions, the from:<person> pill, rows' hover actions, Ctrl+G go-to mode, Communities group. Loop files open as the results page opens them (browser).

- PR #62 (branch task-0366).

- Codex re-review (credits back): 1 new finding (Person ▾ replaced kept the old address keywords), fixed in 67824b97; CI green and Codex clean at 67824b97.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The title bar search now shows Teams desktop's suggestions flyout (PR #62).

Cause: OST had no panel when the box was focused empty, and its as-you-type list was built locally from the chat list (chat rows with initials and "Chat").

Fix:
- src/api/autosuggest.rs: Teams' powerbar requests (zero-query GET, typed POST with Teams' body, headers and flights, captured on winpc) and arrange() into Teams' groups and texts. With nothing typed: People (Teams' top-N) and Suggestions. Typing: Top hits (BestMatchSuggestions), Recent messages (5 + See more), People, Files, Channels, Teams, Group Chats, Meetings, Recent images, Communities. Unit tests included.
- backend.searchSuggest -> suggestJson. The core groups show first; the cached images and Viva Engage communities follow, each with a time limit.
- SearchSuggest.qml: the flyout as measured from Teams' DOM, with the scope pills (they scroll when they don't fit), the Tip or Press Enter footer and Send feedback.
- TitleBar: asks on focus, debounces typing, Up/Down/Enter move and pick; picks open the item as Teams' hostAppActions do. "<person> in all results" opens the results with Person set to them.
- Harness flags: --search-test=<text>, --search-pick=<kind>.

Live: testpc1 WSLg, profile t366 = ost-test1, compared with winpc Teams desktop (same account). The empty-focus panel and the "release" and "ost test" suggestions match Teams' items and texts, and the picks open the right chat, channel, calendar or results.

CI: all checks pass; 9 Codex findings fixed, replied to and resolved. Codex's review of the last commit hit its usage limit.

Follow-up: TASK-0371 (scoped mode after a pill with KQL filter pills, from:<person> pill, rows' hover actions, Ctrl+G go-to mode).
<!-- SECTION:FINAL_SUMMARY:END -->
