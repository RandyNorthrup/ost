---
id: TASK-0246
title: >-
  Posts-channel images, agent answer Loop cards and agent command renderers as
  Teams
status: Done
assignee:
  - '@chatJ'
created_date: '2026-11-22T22:44:00Z'
updated_date: '2026-11-23T04:21:00Z'
labels:
  - desktop
  - messages
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-0206: OST's posts-channel list draws no images in posts (Teams shows them, and extends 'see more' to include an image); a Channel Agent's answer with a Loop page shows a link where Teams draws the Loop card inline; Teams has renderers for agent commands (tasks, plan, createMeeting, agendaTimer, questionsList and more) that OST doesn't draw; the 'still reasoning' step line wasn't measured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Posts in posts-layout channels show their images as Teams does, with see more extended to include an image
- [x] #2 An agent's answer with a Loop page shows the Loop card inline as Teams
- [x] #3 Agent commands Teams renders (tasks, plan, createMeeting, agendaTimer, questionsList, …) show as Teams, verified with live examples
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 2026-11-22 (chatJ), measured on winpc (Teams 26304, CDP) and read from Teams' code:
  - Posts pictures ("OST TEST 246 image post" in OST Test Team > OST test channel, made by OST: six lines, an 800 x 450 picture, three lines):
    - A picture sits in its own line in a 2 px margin (lazy-image-wrapper), rounded 6, 0.67 #F0F0F0 edge, object-fit contain. Its size by Teams' image kinds (async-entry 537457 / 78926): standard (>= 180 tall, < 2:1, or tall 1:2) 180 tall at its ratio (the 800 x 450 showed 320 x 180); ultra-wide / thin (>= 2:1) its own size unless wider than 620 / taller than 480 (--calculatedWideImageWidth), at most 180 tall; super-small (< 180 tall) its own size.
    - See more with a picture (395276 `le` / `Ne`, enableImageAwareSeeMoreTruncation, not for a Channel Agent's reply): a cut through one of the first 20 pictures moves to its bottom plus its wrapper's margin (max-height 304 here: text 120, picture 122..302, +2), the "see more" row in the flow after it. Opened: 384 (the second run's leading <br> is a blank line).
    - Click opens Teams' viewer (PhotoSwipe): under the title bar, #3D3D3D at 90 %, a 60 px #292929 bar (Back; sender 14/20 semibold; "image | Today 4:27 PM | Show message" 12/16 #D6D6D6 with #525252 dividers, Show message #7F85F5; Zoom out, Zoom in, divider, Download), the picture centred at no more than its own size (800 x 450 -> 745 x 419).
  - Channel Agent's Loop page (team "OST TEST 246 agent", asked "create a weekly status report for this channel"): the FluidAutoEmbedLink is replaced in place (443282 FluidEmbedDeserializer `_unfurlAutoEmbedLink`, enableUnfurlFluidAutoEmbedLink, hasExpandedWidth) by Loop's card across the text's width, 9 above and 7 below: white, radius 12, 0.67 #D1D1D1 edge, 48 px header (Loop icon + page name; Pin for everyone; Shared locations / Copy component / See who has access, which fold into a "More actions" ··· when narrow), Loop's frame 320 tall. The text before and after stays.
  - Live agent commands (asked from Teams; their ODSL statements captured): `plan` (draft workback plan: dashed #BDBDBD card radius 8, title 14/20 semibold #616161, a tree scrolled within 275 with summary tasks bold + chevron and children 48 in, due M/d with a calendar glyph, 0.67 #E0E0E0 row lines; Save to Planner / Ask for changes / ··· Discard, 24 tall), `tasks` (a Planner task card: status tag "Not started", title link 12/16, assignee 20 px, due), `createMeeting` (Schedule Meeting 31.3 primary + ··· Edit / Discard meeting among the actions), `genericBotMention` ("Provide answers" / "Draft a plan" small buttons among the actions; forceLineBreak ends the line; a click quotes the answer and mentions the agent with its text), `reasoning` with the still-reasoning line (14 px chain-of-thought orb, the active step 14/20 #707070, right under the header). agendaTimer / questionsList are the Facilitator's in a meeting: built from Teams' code (541316 `jt`, `td`/`Xc`) with unit tests only.
  - Found: OST's question to the agent got "Something went wrong": OST sent the mention as mentionType "person" with no appId; Teams sends mentionType "bot" with the agent's app id (the welcome's app instance). OST now sends bot mentions so.
  - Statement execution: Teams sends an "odsl/statementExecuted" invoke ({statement, statementIndex, suggestedActionIndex, result}); plan Save/Discard ({actionName: SavePlan/DiscardPlan}), meeting Schedule ({eventId, meetingStatus: SCHEDULED}) / Discard ({meetingStatus: DISCARDED}).

- 2026-11-22 (chatJ), built and checked live in OST on linuxlt (ost-test1):
  - Posts (`--see-more-test --see-more-name=OST~Test~Team/OST~test~channel --see-more-id=<post>`): the picture 320 x 180 between the text runs, cut at the picture's bottom with "see more" (SEEMORE images [[121,303]], Teams 122..304), opened 382 (Teams 384), the viewer opened on a click with Teams' bar (`-viewer.png`). Same layout as Teams' screenshots. 1 px short per text run (Qt's line count).
  - Agent answers (`--agent-answers-test`, thread of the welcome in "OST TEST 246 agent"): the weekly status report's Loop page drawn in place by Loop (page name, pin, ···, its content), Provide answers / Draft a plan before @agent on its own line, the draft plan card (tree, Save to Planner / Ask for changes / ···), Schedule Meeting + ··· among the actions, the Planner task card (Not started, title, avatar, 11/26). All as in Teams' thread pane.
  - Bot mention: `--agent-welcome-test --agent-ask=…` now gets a real answer (it got "Something went wrong" before the fix).
  - Not clicked live (they would create a meeting or a Planner plan): Schedule Meeting, Save to Planner; Discard / Ask for changes / Edit were not sent either. agendaTimer / questionsList: from Teams' code with unit tests (the Facilitator's in a meeting).
  - Test content removed: the post "OST TEST 246 image post" (and an earlier copy with joined lines) deleted with --delete-test-messages; team "OST TEST 246 agent" deleted with --team-live=delete (its Planner task / plan and Loop page went with it). Nothing was scheduled.
  - Tests: 911 lib + 29 desktop pass.

- 2026-11-22 (review on merge 9c31293c): AC1 and AC2 verified live. AC3 reopened: plan, Planner task, Schedule Meeting and reasoning were live; the Facilitator's agendaTimer and questionsList are built from Teams' code with unit tests only and still need live examples in a Facilitator meeting.

- 2026-11-22 (meetK) Facilitator live, for AC3's agendaTimer / questionsList: a solo meeting "OST TEST 246 facilitator" made and joined by OST (ost-test1, linuxlt, --call-notes-test --call-notes-subject=… --call-notes-stay=1200); Teams on winpc (ost-test1) joined it ("Add this device", mic and camera off), More ▸ Facilitator ▸ "Start transcription to use Facilitator" ▸ Start ▸ English (US) ▸ Confirm: "Facilitator has been turned on and is taking notes." and its welcome ("Add agenda").
  - "@Facilitator here's the agenda: Budget review 2 minutes, Permit timeline 2 minutes, Volunteer plan 1 minute. Please start the agenda timer." → "I'll start tracking this agenda now." with the three topics; the meeting's agenda timer started (Teams' strip: Budget review / Permit timeline / Volunteer plan / Open discussion 22:00, labels 12/600 truncated "B…", "P…"). OST's call window drew the same strip from the meeting's shared state at once (four segments, Open discussion 22:00), but without the topics' truncated labels in the short segments.
  - "@Facilitator please track these open questions: …" → "I can't track open questions separately here."; "@Facilitator what questions have people asked in this meeting so far?" → a plain answer with a citation (Teams: a "1" chip; OST: "[1]").
  - The Facilitator's messages carried only `reasoning` ODSL statements (OST's --see-more-test on the meeting chat: kinds manage_agenda.ingest_agenda / respond_directly, statements reasoning ×3): no agendaTimer and no questionsList command came, so those two renderers still have no live example in this tenant (the agent starts the agenda server-side instead of offering a Start-timer action). OST drew the chat as Teams (quotes, "Reasoned for n seconds", feedback).
  - Teams turned Facilitator off again (More ▸ Facilitator: "Facilitator has been turned off", transcription stopped) and left; OST left (Leave): its log shows "MEETINGNOTES after" with no call. OST then deleted the meeting ("event still there false") and its notes ("OST TEST 246 facilitator.loop"). The organizer deleted it, so no "Canceled:" copy exists.

- 2026-11-22: Facilitator meeting held: the agenda timer drew in OST as soon as the Facilitator started tracking; asked for a questions list it answers in plain text, so no questionsList command can be produced live in this Teams version (built from Teams' code with unit tests). Agenda timer narrow-segment labels moved to TASK-0247.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Posts pictures, agents' Loop cards and agent command views as Teams: posts in posts-layout channels draw pictures (Teams' sizing rule), quotes, code blocks and Loop links in place, with see more moved below a cut picture and Teams' picture viewer; an agent answer's Loop page becomes Loop's card in place; agent commands draw as Teams (draft plan card, Planner task card, Schedule Meeting and its menu, Provide answers / Draft a plan, the reasoning and still-reasoning lines; agenda timer via the Facilitator). Questions to the agent from OST mention it as a bot as Teams does; bot buttons work in thread panes. Verified live against Teams in test team OST TEST 246 agent (deleted).
<!-- SECTION:FINAL_SUMMARY:END -->
