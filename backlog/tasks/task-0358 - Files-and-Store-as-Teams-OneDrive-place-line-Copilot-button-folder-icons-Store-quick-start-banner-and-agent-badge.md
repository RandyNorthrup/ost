---
id: TASK-0358
title: >-
  Files and Store as Teams: OneDrive place line, Copilot button, folder icons;
  Store quick start, banner and agent badge
status: Done
assignee:
  - '@claude-task-0358'
created_date: '2026-11-27T17:32:00Z'
updated_date: '2026-11-27T20:19:00Z'
labels: []
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-11-27 parity audit (scope B), which compared Teams desktop on winpc (ost-test1, read over CDP) with OST main 7d1c3a38 on linuxlt. Each acceptance criterion is one verified gap. The full entry for each (what Teams does, what OST does, severity, evidence) is in /home/randy/.local/share/ost-remaining/audit/auditB.md, under its B-number, with screenshots in audit/shots-B/ (t-* Teams, o-* OST).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 B-11: Store: an installed app's card opens Teams' "Let's go" quick-start dialog, as Teams desktop does it, checked side by side
- [x] #2 B-23: OneDrive: place line for files in someone else's subfolder, as Teams desktop does it, checked side by side
- [x] #3 B-24: OneDrive folder view: "Copilot ▾" button in the header, as Teams desktop does it, checked side by side
- [x] #4 B-25: OneDrive folder view: shared-folder and shortcut folder icons, as Teams desktop does it, checked side by side
- [x] #5 B-26: Store home: banner artwork and the agent badge on app names, as Teams desktop does it, checked side by side
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research each gap in Teams desktop (testpc1 over read-only CDP) and in Teams' and OneDrive's own bundles.
2. B-23: port OneDrive's getContainerTitle.odb to recent_files::location (My/Their Files, Whiteboards, Lists).
3. B-26: Store banner = gradient + runtime-loaded evergreen ribbon pictures; marks after app names (certified, agent sparkle).
4. B-11: ContextlessDialog.qml (Let's go) opened by cards of installed apps; places from teams/chats/calendar (api::app_places, team list fields); Go sets up the tab or adds the app.
5. B-24: Copilot ▾ in My files header/subfolder bar with Ask a question opening OdspCopilotPane with no file.
6. B-25: shared-folder People glyph and shortcut badge overlays, shortcut Sharing glyph.
7. Unit tests, build, live checks on linuxlt vs testpc1, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Research (testpc1 Teams 26304 over CDP, 2026-11-27): Let's go = app details' ContextlessConfigPicker (store item click 320414, places resolver appInstallOptions in worker inner~d); OneDrive place line = getContainerTitle.odb (file browser bundle 2026-11-13); banner ribbons are evergreen-assets/apps/store/header_ribbon_{left,right}[_dark].png; marks Certified/Sparkle; folder overlays module 4852/4853; Copilot ▾ menu = Ask a question.
- Gotcha: testpc1 WebView2's CDP HTTP endpoint (json/list) hangs for minutes after heavy page scripts; the audit tc.py evaluated each js 2-3 times. Keep a page websocket URL and use it directly.

- Built (testpc1 WSL) and checked live on linuxlt as ost-test1 (QML via OST_QML_DIR, a local eval tour), side by side with Teams on testpc1:
  - B-26: the banner now shows Teams' ribbon pictures (loaded at run time from teams.public.onecdn.static.microsoft) over the #E8EBFA→white gradient; the 580 px search with its brand foot line. Sparkle on Jira, Cowork, Mural, Decisions, Klaxoon and the certified shield on ClickUp, CoffeePals: the same apps as Teams.
  - B-11: Power BI's card opens "Let's go" (Open, Or choose a place, search, channels/chats/meetings, picked row, Go footer, sticky "Choose where to get started"); Go on OST test channel opened the channel and Power BI's tab configuration (closed without saving).
  - B-23: Home rows read "OST Test 3's Whiteboards" and "My Files" as Teams.
  - B-24: My files shows Copilot ▾ (menu: Ask a question) and the subfolder bar has it after Copy link; Ask a question opens the Copilot pane with OneDrive's three prompts.
  - B-25: Meetings/Recordings carry the People glyph, OST Test Team - General the glyph plus the shortcut badge and ArrowSquareUpRight before Owner.
- Differences left: Teams' chat places on testpc1 also leave out a few chats OST lists (Just me, OST TEST 348 *); the reason isn't in the resolver code I read (Teams' chat-list visibility filter `te.lb`). Teams' Home also lists a loop_loopThread item OST leaves out (separate from B-23). Tiles view folder marks not added. OneDrive's knowledge agent state for Ask a question is left out, as for Summarize.

- PR #50. Codex review rounds fixed: channel meetings only for apps that work in channels and with their channel's checks; calendar meetings kept when their chat isn't listed yet (now shows Weekly team sync as Teams); Ask a question after Summarize drops the file's source; tab config Back returns to the quick start; Go clears chat subviews; config URL from the definition; tab places follow Add a tab's scope+context rules (meeting tabs: any meeting surface); messageExtensions count as personal. shared_files test fixture gained ContentClass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Files and Store now match Teams desktop for the five scope-B audit gaps.

- B-11: a Store card of an app you have opens Teams' quick-start dialog ("Let's go", new ContextlessDialog.qml): Open, "Or choose a place to use the app", a search naming the supported places, channels / chats / meetings with View more, and Go, which opens the place and sets the app's tab up there or adds the app (bot @mention). Places come from the team list (now with read horizons, favourite and app permissions), the chat list and your calendar's Teams meetings (new api::app_places). App details carry the manifest's accent colour and its install scopes (app_details::places).
- B-23: recent_files::location follows OneDrive's getContainerTitle.odb: My Files / My Whiteboards / My Lists, "{owner}'s Files / Whiteboards / Lists", a site's title, a mail attachment's subject.
- B-24: Copilot ▾ in My files' header and a My files subfolder's bar; Ask a question opens OneDrive's Copilot pane with no file and its zero-query prompts.
- B-25: shared folders and shortcuts carry OneDrive's People glyph in the folder colour's shade; shortcuts also OneDrive's shortcut badge (loaded at run time) and ArrowSquareUpRight before "Owner: …".
- B-26: the Store banner shows Teams' ribbon pictures (its public evergreen assets, loaded at run time) over Teams' gradient, with its search styling; Certified and agent (Sparkle) marks after app names.

No Teams artwork is committed: the ribbon, shortcut badge and colored Copilot pictures load from Microsoft's CDNs; the two new glyphs are Fluent UI System Icons (MIT).

Tests: recent_files::place_line_as_onedrive, app_details::places_as_teams_picker, app_places::upcoming_first_then_past_each_place_once. Live: linuxlt (ost-test1) beside Teams on testpc1.

Left: a few chats Teams leaves out of the places list (reason not found), tiles-view folder marks, OneDrive's knowledge agent state.
<!-- SECTION:FINAL_SUMMARY:END -->
